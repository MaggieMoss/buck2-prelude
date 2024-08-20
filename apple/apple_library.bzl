# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under both the MIT license found in the
# LICENSE-MIT file in the root directory of this source tree and the Apache
# License, Version 2.0 found in the LICENSE-APACHE file in the root directory
# of this source tree.

load(
    "@prelude//:artifact_tset.bzl",
    "ArtifactInfoTag",
    "ArtifactTSet",
    "make_artifact_tset",
    "project_artifacts",
)
load("@prelude//:attrs_validators.bzl", "get_attrs_validators_specs")
load("@prelude//:validation_deps.bzl", "get_validation_deps_outputs")
load("@prelude//apple:apple_dsym.bzl", "DSYM_SUBTARGET", "get_apple_dsym")
load("@prelude//apple:apple_error_handler.bzl", "apple_build_error_handler")
load("@prelude//apple:apple_stripping.bzl", "apple_strip_args")
load("@prelude//apple:apple_toolchain_types.bzl", "AppleToolchainInfo")
# @oss-disable: load("@prelude//apple/meta_only:linker_outputs.bzl", "add_extra_linker_outputs") 
load(
    "@prelude//apple/swift:swift_compilation.bzl",
    "SwiftLibraryForDistributionOutput",  # @unused Used as a type
    "compile_swift",
    "get_swift_anonymous_targets",
    "get_swift_debug_infos",
    "get_swift_dependency_info",
    "get_swift_pcm_uncompile_info",
    "get_swiftmodule_linkable",
    "uses_explicit_modules",
)
load("@prelude//apple/swift:swift_types.bzl", "SWIFT_EXTENSION")
load(
    "@prelude//cxx:argsfiles.bzl",
    "CompileArgsfile",  # @unused Used as a type
    "CompileArgsfiles",
)
load(
    "@prelude//cxx:cxx_library.bzl",
    "CxxLibraryOutput",  # @unused Used as a type
    "cxx_library_parameterized",
)
load(
    "@prelude//cxx:cxx_library_utility.bzl",
    "cxx_attr_deps",
    "cxx_attr_exported_deps",
)
load(
    "@prelude//cxx:cxx_sources.bzl",
    "CxxSrcWithFlags",  # @unused Used as a type
    "get_srcs_with_flags",
)
load(
    "@prelude//cxx:cxx_types.bzl",
    "CxxRuleAdditionalParams",
    "CxxRuleConstructorParams",
    "CxxRuleProviderParams",
    "CxxRuleSubTargetParams",
)
load("@prelude//cxx:headers.bzl", "cxx_attr_exported_headers", "cxx_attr_headers_list")
load(
    "@prelude//cxx:linker.bzl",
    "SharedLibraryFlagOverrides",
)
load(
    "@prelude//cxx:preprocessor.bzl",
    "CPreprocessor",
    "CPreprocessorArgs",
    "CPreprocessorInfo",  # @unused Used as a type
)
load(
    "@prelude//linking:link_info.bzl",
    "LibOutputStyle",
)
load("@prelude//utils:arglike.bzl", "ArgLike")
load("@prelude//utils:expect.bzl", "expect")
load("@prelude//apple/mockingbird/mockingbird_types.bzl", "MockingbirdLibraryInfo", "MockingbirdLibraryInfoTSet", "MockingbirdLibraryRecord", "MockingbirdSourcesInfo", "MockingbirdTargetType")
load(":apple_bundle_types.bzl", "AppleBundleLinkerMapInfo", "AppleMinDeploymentVersionInfo")
load(":apple_frameworks.bzl", "get_framework_search_path_flags")
load(":apple_modular_utility.bzl", "MODULE_CACHE_PATH")
load(":apple_target_sdk_version.bzl", "get_min_deployment_version_for_node", "get_min_deployment_version_target_preprocessor_flags", "get_unversioned_target_triple")
load(":apple_utility.bzl", "get_apple_cxx_headers_layout", "get_apple_stripped_attr_value_with_default_fallback", "get_module_name")
load(
    ":debug.bzl",
    "AppleDebuggableInfo",
    "DEBUGINFO_SUBTARGET",
)
load(":modulemap.bzl", "preprocessor_info_for_modulemap")
load(":resource_groups.bzl", "create_resource_graph")
load(":xcode.bzl", "apple_populate_xcode_attributes")
load(":xctest_swift_support.bzl", "xctest_swift_support_info")

AppleSharedLibraryMachOFileType = enum(
    # dynamically bound shared library file
    "dylib",
    # dynamically bound bundle file aka Mach-O bundle
    "bundle",
)

AppleLibraryAdditionalParams = record(
    # Name of the top level rule utilizing the apple_library rule.
    rule_type = str,
    # Extra flags to be passed to the linker.
    extra_exported_link_flags = field(list[ArgLike], []),
    # Extra flags to be passed to the Swift compiler.
    extra_swift_compiler_flags = field(list[ArgLike], []),
    # Linker flags that tell the linker to create shared libraries, overriding the default shared library flags.
    # e.g. when building Apple tests, we want to link with `-bundle` instead of `-shared` to allow
    # linking against the bundle loader.
    shared_library_flags = field([SharedLibraryFlagOverrides, None], None),
    # Function to use for setting Xcode attributes for the Xcode data sub target.
    populate_xcode_attributes_func = field(typing.Callable, apple_populate_xcode_attributes),
    # Define which sub targets to generate.
    generate_sub_targets = field(CxxRuleSubTargetParams, CxxRuleSubTargetParams()),
    # Define which providers to generate.
    generate_providers = field(CxxRuleProviderParams, CxxRuleProviderParams()),
    # Forces link group linking logic, even when there's no mapping. Link group linking
    # without a mapping is equivalent to statically linking the whole transitive dep graph.
    force_link_group_linking = field(bool, False),
)

AppleLibraryForDistributionInfo = provider(
    fields = {
        "module_name": str,
        "private_swiftinterface": Artifact,
        "swiftdoc": Artifact,
        "swiftinterface": Artifact,
        "target_triple": str,
    },
)
AppleLibraryInfo = provider(
    fields = {
        "public_framework_headers": ArtifactTSet,
        "swift_header": [Artifact, None],
    },
)

def apple_library_impl(ctx: AnalysisContext) -> [Promise, list[Provider]]:
    def get_apple_library_providers(deps_providers) -> list[Provider]:
        shared_type = AppleSharedLibraryMachOFileType(ctx.attrs.shared_library_macho_file_type)
        if shared_type == AppleSharedLibraryMachOFileType("bundle"):
            shared_library_flags_overrides = SharedLibraryFlagOverrides(
                # When `-bundle` is used we can't use the `-install_name` args, thus we keep this field empty.
                shared_library_name_linker_flags_format = [],
                shared_library_flags = ["-bundle"],
            )
        elif shared_type == AppleSharedLibraryMachOFileType("dylib"):
            shared_library_flags_overrides = None
        else:
            fail("Unsupported `shared_library_macho_file_type` attribute value: `{}`".format(shared_type))
        constructor_params = apple_library_rule_constructor_params_and_swift_providers(
            ctx,
            AppleLibraryAdditionalParams(
                rule_type = "apple_library",
                generate_providers = CxxRuleProviderParams(
                    java_packaging_info = False,
                    android_packageable_info = False,
                    omnibus_root = False,
                    # We generate a provider on our own, disable to avoid several providers of same type.
                    cxx_resources_as_apple_resources = False,
                ),
                shared_library_flags = shared_library_flags_overrides,
            ),
            deps_providers,
        )
        output = cxx_library_parameterized(ctx, constructor_params)

        return output.providers + _make_mockingbird_library_info_provider(ctx)

    if uses_explicit_modules(ctx):
        return get_swift_anonymous_targets(ctx, get_apple_library_providers)
    else:
        return get_apple_library_providers([])

def _make_apple_library_for_distribution_info_provider(ctx: AnalysisContext, swift_library_for_distribution: [None, SwiftLibraryForDistributionOutput]) -> list[AppleLibraryForDistributionInfo]:
    if not swift_library_for_distribution:
        return []
    return [AppleLibraryForDistributionInfo(
        target_triple = get_unversioned_target_triple(ctx).replace("macosx", "macos"),
        swiftinterface = swift_library_for_distribution.swiftinterface,
        private_swiftinterface = swift_library_for_distribution.private_swiftinterface,
        swiftdoc = swift_library_for_distribution.swiftdoc,
        module_name = get_module_name(ctx),
    )]

def _make_apple_library_info_provider(ctx: AnalysisContext, swift_header: [None, Artifact]) -> list[AppleLibraryInfo]:
    public_framework_headers = cxx_attr_headers_list(ctx, ctx.attrs.public_framework_headers, [], get_apple_cxx_headers_layout(ctx))
    all_deps = cxx_attr_deps(ctx) + cxx_attr_exported_deps(ctx)
    apple_library_infos = filter(None, [dep.get(AppleLibraryInfo) for dep in all_deps])

    public_framework_header_tset = make_artifact_tset(
        actions = ctx.actions,
        label = ctx.label,
        artifacts = [header.artifact for header in public_framework_headers],
        children = [apple_library.public_framework_headers for apple_library in apple_library_infos],
    )

    return [AppleLibraryInfo(public_framework_headers = public_framework_header_tset, swift_header = swift_header)]

def _make_mockingbird_library_info_provider(ctx: AnalysisContext) -> list[MockingbirdLibraryInfo]:
    _, swift_sources = _filter_swift_srcs(ctx)

    if len(swift_sources) == 0:
        return []

    deps_mockingbird_infos = filter(None, [dep.get(MockingbirdLibraryInfo) for dep in cxx_attr_deps(ctx)])
    exported_deps_mockingbird_infos = filter(None, [dep.get(MockingbirdLibraryInfo) for dep in cxx_attr_exported_deps(ctx)])

    children = []
    dep_names = []
    exported_dep_names = []
    for info in deps_mockingbird_infos:
        dep_names.append(info.name)
        children.append(info.tset)

    for info in exported_deps_mockingbird_infos:
        exported_dep_names.append(info.name)
        children.append(info.tset)

    mockingbird_srcs_folder = ctx.actions.declare_output("mockingbird_srcs_" + ctx.attrs.name, dir = True)

    ctx.actions.symlinked_dir(
        mockingbird_srcs_folder,
        {source.file.basename: source.file for source in swift_sources},
    )

    mockingbird_record = MockingbirdLibraryRecord(
        name = ctx.attrs.name,
        srcs = [src.file for src in swift_sources],
        dep_names = dep_names,
        exported_dep_names = exported_dep_names,
        type = MockingbirdTargetType("library"),
        src_dir = mockingbird_srcs_folder,
    )

    mockingbird_tset = ctx.actions.tset(MockingbirdLibraryInfoTSet, value = mockingbird_record, children = children)

    return [MockingbirdLibraryInfo(
        name = ctx.attrs.name,
        tset = mockingbird_tset,
    )]

def apple_library_rule_constructor_params_and_swift_providers(ctx: AnalysisContext, params: AppleLibraryAdditionalParams, deps_providers: list = [], is_test_target: bool = False) -> CxxRuleConstructorParams:
    mockingbird_gen_sources = []
    if not "dummy_library" in ctx.attrs.labels:
        for dep in cxx_attr_deps(ctx) + cxx_attr_exported_deps(ctx):
            if MockingbirdSourcesInfo in dep:
                for src in dep[MockingbirdSourcesInfo].srcs:
                    mockingbird_gen_sources.append(src)

    cxx_srcs, swift_srcs = _filter_swift_srcs(ctx, mockingbird_gen_sources)

    # First create a modulemap if necessary. This is required for importing
    # ObjC code in Swift so must be done before Swift compilation.
    exported_hdrs = cxx_attr_exported_headers(ctx, get_apple_cxx_headers_layout(ctx))
    if (ctx.attrs.modular or swift_srcs) and exported_hdrs:
        modulemap_pre = preprocessor_info_for_modulemap(ctx, "exported", exported_hdrs, None)
    else:
        modulemap_pre = None

    framework_search_paths_flags = get_framework_search_path_flags(ctx)
    swift_compile, swift_interface = compile_swift(
        ctx,
        swift_srcs,
        True,  # parse_as_library
        deps_providers,
        exported_hdrs,
        modulemap_pre,
        framework_search_paths_flags,
        params.extra_swift_compiler_flags,
    )
    swift_object_files = swift_compile.object_files if swift_compile else []

    swift_pre = CPreprocessor()
    if swift_compile:
        # If we have Swift we export the extended modulemap that includes
        # the ObjC exported headers and the -Swift.h header.
        exported_pre = swift_compile.exported_pre

        # We also include the -Swift.h header to this libraries preprocessor
        # info, so that we can import it unprefixed in this module.
        swift_pre = swift_compile.pre
    elif modulemap_pre:
        # Otherwise if this library is modular we export a modulemap of
        # the ObjC exported headers.
        exported_pre = modulemap_pre
    else:
        exported_pre = None

    swift_dependency_info = swift_compile.dependency_info if swift_compile else get_swift_dependency_info(ctx, None, deps_providers)
    swift_debug_info = get_swift_debug_infos(
        ctx,
        swift_dependency_info,
        swift_compile,
    )

    swift_toolchain = ctx.attrs._apple_toolchain[AppleToolchainInfo].swift_toolchain_info
    if swift_toolchain and swift_toolchain.supports_relative_resource_dir:
        resource_dir_args = []
    else:
        # We have to use this hack to make compilation work when Clang modules
        # are enabled and using toolchains that don't support relative resource
        # directories correctly. The builtin headers will be embedded relative
        # to the CWD, so need to add . to be located correctly.
        resource_dir_args = ["-I."]

    modular_pre = CPreprocessor(
        uses_modules = ctx.attrs.uses_modules,
        modular_args = [
            "-fcxx-modules",
            "-fmodules",
            "-fmodule-name=" + get_module_name(ctx),
            "-fmodules-cache-path=" + MODULE_CACHE_PATH,
        ] + resource_dir_args,
    )

    contains_swift_sources = bool(swift_srcs)
    xctest_swift_support_provider = xctest_swift_support_info(ctx, contains_swift_sources, is_test_target)

    def additional_providers_factory(propagated_exported_preprocessor_info: [CPreprocessorInfo, None]) -> list[Provider]:
        # Expose `SwiftPCMUncompiledInfo` which represents the ObjC part of a target,
        # if a target also has a Swift part, the provider will expose the generated `-Swift.h` header.
        # This is used for Swift Explicit Modules, and allows compiling a PCM file out of the exported headers.
        swift_pcm_uncompile_info = get_swift_pcm_uncompile_info(
            ctx,
            propagated_exported_preprocessor_info,
            exported_pre,
        )
        providers = [swift_pcm_uncompile_info] if swift_pcm_uncompile_info else []
        providers.append(swift_dependency_info)
        providers.append(xctest_swift_support_provider)

        validation_specs = get_attrs_validators_specs(ctx)
        if validation_specs:
            providers.append(ValidationInfo(validations = validation_specs))

        return providers

    framework_search_path_pre = CPreprocessor(
        args = CPreprocessorArgs(args = [framework_search_paths_flags]),
    )

    validation_deps_outputs = get_validation_deps_outputs(ctx)
    if swift_compile:
        swift_objc_header = swift_compile.exported_swift_header
        swift_library_for_distribution_output = swift_compile.swift_library_for_distribution_output
    else:
        swift_objc_header = None
        swift_library_for_distribution_output = None

    extra_apple_providers = []
    if not is_test_target:
        extra_apple_providers = _make_apple_library_info_provider(ctx, swift_objc_header) + _make_apple_library_for_distribution_info_provider(ctx, swift_library_for_distribution_output)

    return CxxRuleConstructorParams(
        rule_type = params.rule_type,
        is_test = (params.rule_type == "apple_test"),
        headers_layout = get_apple_cxx_headers_layout(ctx),
        extra_exported_link_flags = params.extra_exported_link_flags,
        extra_hidden = validation_deps_outputs,
        extra_link_input = swift_object_files,
        extra_link_input_has_external_debug_info = True,
        extra_preprocessors = get_min_deployment_version_target_preprocessor_flags(ctx) + [swift_pre, modular_pre],
        extra_exported_preprocessors = filter(None, [framework_search_path_pre, exported_pre]),
        srcs = cxx_srcs,
        additional = CxxRuleAdditionalParams(
            srcs = swift_srcs,
            argsfiles = swift_compile.argsfiles if swift_compile else CompileArgsfiles(),
            # We need to add any swift modules that we include in the link, as
            # these will end up as `N_AST` entries that `dsymutil` will need to
            # follow.
            static_external_debug_info = swift_debug_info.static,
            shared_external_debug_info = swift_debug_info.shared,
            subtargets = {
                "swift-compilation-database": [
                    DefaultInfo(
                        default_output = swift_compile.compilation_database.db if swift_compile else None,
                        other_outputs = [swift_compile.compilation_database.other_outputs] if swift_compile else [],
                    ),
                ],
                "swift-compile": [
                    DefaultInfo(
                        default_outputs = swift_compile.object_files if swift_compile else None,
                    ),
                ],
                "swift-interface": [swift_interface],
                "swift-output-file-map": [
                    DefaultInfo(
                        default_output = swift_compile.output_map_artifact if swift_compile else None,
                    ),
                ],
                "swiftmodule": [
                    DefaultInfo(
                        default_output = swift_compile.swiftmodule if swift_compile else None,
                    ),
                ],
            },
            additional_providers_factory = additional_providers_factory,
            external_debug_info_tags = [ArtifactInfoTag("swiftmodule")] if swift_compile else [],
        ),
        output_style_sub_targets_and_providers_factory = _get_link_style_sub_targets_and_providers(extra_apple_providers),
        shared_library_flags = params.shared_library_flags,
        # apple_library's 'stripped' arg only applies to shared subtargets, or,
        # targets with 'preferred_linkage = "shared"'
        strip_executable = get_apple_stripped_attr_value_with_default_fallback(ctx),
        strip_args_factory = apple_strip_args,
        force_link_group_linking = params.force_link_group_linking,
        cxx_populate_xcode_attributes_func = lambda local_ctx, **kwargs: _xcode_populate_attributes(ctx = local_ctx, populate_xcode_attributes_func = params.populate_xcode_attributes_func, contains_swift_sources = contains_swift_sources, **kwargs),
        generate_sub_targets = params.generate_sub_targets,
        generate_providers = params.generate_providers,
        # Some apple rules rely on `static` libs *not* following dependents.
        link_groups_force_static_follows_dependents = False,
        extra_linker_outputs_factory = _get_extra_linker_flags_and_outputs,
        swiftmodule_linkable = get_swiftmodule_linkable(swift_compile),
        extra_shared_library_interfaces = [swift_compile.exported_symbols] if (swift_compile and swift_compile.exported_symbols) else None,
        compiler_flags = ctx.attrs.compiler_flags,
        lang_compiler_flags = ctx.attrs.lang_compiler_flags,
        platform_compiler_flags = ctx.attrs.platform_compiler_flags,
        lang_platform_compiler_flags = ctx.attrs.lang_platform_compiler_flags,
        preprocessor_flags = ctx.attrs.preprocessor_flags,
        lang_preprocessor_flags = ctx.attrs.lang_preprocessor_flags,
        platform_preprocessor_flags = ctx.attrs.platform_preprocessor_flags,
        lang_platform_preprocessor_flags = ctx.attrs.lang_platform_preprocessor_flags,
        swift_objc_header = swift_objc_header,
        error_handler = apple_build_error_handler,
    )

def _get_extra_linker_flags_and_outputs(
        ctx: AnalysisContext) -> (list[ArgLike], dict[str, list[DefaultInfo]]):
    _ = ctx  # buildifier: disable=unused-variable
    # @oss-disable: return add_extra_linker_outputs(ctx) 
    return [], {} # @oss-enable

def _filter_swift_srcs(ctx: AnalysisContext, additional_srcs: list = []) -> (list[CxxSrcWithFlags], list[CxxSrcWithFlags]):
    cxx_srcs = []
    swift_srcs = []
    for s in get_srcs_with_flags(ctx, additional_srcs):
        if s.file.extension == SWIFT_EXTENSION:
            swift_srcs.append(s)
        else:
            cxx_srcs.append(s)

    return cxx_srcs, swift_srcs

def _get_link_style_sub_targets_and_providers(
        extra_providers: list[Provider]) -> typing.Callable:
    def get_link_style_sub_targets_impl(
            output_style: LibOutputStyle,
            ctx: AnalysisContext,
            output: [CxxLibraryOutput, None]) -> (dict[str, list[Provider]], list[Provider]):
        # We always propagate a resource graph regardless of link style or empty output
        resource_graph = create_resource_graph(
            ctx = ctx,
            labels = ctx.attrs.labels,
            deps = cxx_attr_deps(ctx),
            exported_deps = cxx_attr_exported_deps(ctx),
            # Shared libraries should not propagate their resources to rdeps,
            # they should only be contained in their frameworks apple_bundle.
            should_propagate = output_style != LibOutputStyle("shared_lib"),
        )

        if output_style != LibOutputStyle("shared_lib") or output == None:
            return ({}, [resource_graph] + extra_providers)

        min_version = get_min_deployment_version_for_node(ctx)
        min_version_providers = [AppleMinDeploymentVersionInfo(version = min_version)]

        debug_info = project_artifacts(
            actions = ctx.actions,
            tsets = [output.external_debug_info],
        )

        if get_apple_stripped_attr_value_with_default_fallback(ctx):
            if False:
                # TODO(nga): `output.unstripped` is never `None`.
                def unknown():
                    pass

                output = unknown()
            expect(output.unstripped != None, "Expecting unstripped output to be non-null when stripping is enabled.")
            dsym_executable = output.unstripped
        else:
            dsym_executable = output.default
        dsym_artifact = get_apple_dsym(
            ctx = ctx,
            executable = dsym_executable,
            debug_info = debug_info,
            action_identifier = dsym_executable.short_path,
        )
        debug_info_artifacts_manifest = ctx.actions.write(
            "debuginfo.artifacts",
            debug_info,
            with_inputs = True,
        )
        subtargets = {
            DSYM_SUBTARGET: [DefaultInfo(default_output = dsym_artifact)],
            DEBUGINFO_SUBTARGET: [DefaultInfo(default_output = debug_info_artifacts_manifest)],
        }
        providers = [
            AppleDebuggableInfo(dsyms = [dsym_artifact], debug_info_tset = output.external_debug_info),
            resource_graph,
        ] + min_version_providers + extra_providers

        if output.linker_map != None:
            subtargets["linker-map"] = [DefaultInfo(default_output = output.linker_map.map, other_outputs = [output.linker_map.binary])]
            providers += [AppleBundleLinkerMapInfo(linker_maps = [output.linker_map.map])]

        return (subtargets, providers)

    return get_link_style_sub_targets_impl

def _xcode_populate_attributes(
        ctx,
        srcs: list[CxxSrcWithFlags],
        argsfiles: dict[str, CompileArgsfile],
        populate_xcode_attributes_func: typing.Callable,
        contains_swift_sources: bool,
        **_kwargs) -> dict[str, typing.Any]:
    # Overwrite the product name
    data = populate_xcode_attributes_func(ctx, srcs = srcs, argsfiles = argsfiles, product_name = ctx.attrs.name, contains_swift_sources = contains_swift_sources)
    return data
