# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under both the MIT license found in the
# LICENSE-MIT file in the root directory of this source tree and the Apache
# License, Version 2.0 found in the LICENSE-APACHE file in the root directory
# of this source tree.

# TODO(cjhopman): This was generated by scripts/hacks/rules_shim_with_docs.py,
# but should be manually edited going forward. There may be some errors in
# the generated docs, and so those should be verified to be accurate and
# well-formatted (and then delete this TODO)

load(":common.bzl", "ForkMode", "LogLevel", "SourceAbiVerificationMode", "TestType", "UnusedDependenciesAction", "prelude_rule")
load(":jvm_common.bzl", "jvm_common")

groovy_library = prelude_rule(
    name = "groovy_library",
    docs = """
        A `groovy_library()` rule is used to define a set of Groovy files that can be compiled
        together. It can also be used to cross compile a set of Groovy and Java files. The main output of a
         `groovy_library()` rule is a single JAR file containing all of the compiled class
        files and resources.
    """,
    examples = """
        ```

        # A rule that compiles a single .groovy file.
        groovy_library(
          name = 'example',
          srcs = ['MySourceFile.groovy'],
        )

        ```


        ```

        # A rule that compiles all of the .groovy files under the directory in
        # which the rule is defined using glob()
        groovy_library(
          name = 'groovy-only',
          srcs = glob(['**/*.groovy']),
        )

        ```


        ```

        # A rule that cross compiles all of the .groovy and .java files under
        # the directory in which the rule is defined, failing if compiling the
        # java files generates any compiler warnings
        groovy_library(
          name = 'cross-compilation',
          srcs = glob(['**/*.groovy', '**/*.java']),
          java_version = 8,
          extra_arguments = [
            '-Werror',
          ],
        )

        ```
    """,
    further = None,
    attrs = (
        # @unsorted-dict-items
        {
            "srcs": attrs.list(attrs.source(), default = [], doc = """
                The set of files to compile for this rule.
                 Usually these will all end in `.groovy`, but if any of the files end in
                 `.java`, cross compilation using the jdk found in `JAVA_HOME` will occur.
            """),
            "resources": attrs.list(attrs.source(), default = [], doc = """
                This is the same as in `java_library()`.
            """),
            "deps": attrs.list(attrs.dep(), default = [], doc = """
                Rules (usually other `groovy_library` or ``java_library()`` rules)
                 that are used to generate the classpath required to compile this `groovy_library`.

                 This is the same as in `java_library()`.
            """),
            "exported_deps": attrs.list(attrs.dep(), default = [], doc = """
                Other `groovy_library` and ``java_library()`` rules that depend
                 on this rule will also include its `exported_deps` in their classpaths.

                 This is the same as in `java_library()`.
            """),
            "provided_deps": attrs.list(attrs.dep(), default = [], doc = """
                This is the same as in `java_library()`.
            """),
            "extra_groovyc_arguments": attrs.list(attrs.string(), default = [], doc = """
                List of additional arguments to pass into the Groovy compiler.
            """),
            "source": attrs.option(attrs.string(), default = None, doc = """
                Only used during cross compilation.

                 This is the same as in `java_library()`.
            """),
            "target": attrs.option(attrs.string(), default = None, doc = """
                Only used during cross compilation.

                 This is the same as in `java_library()`.
            """),
            "java_version": attrs.option(attrs.string(), default = None, doc = """
                Only used during cross compilation.

                 This is the same as in `java_library()`.
            """),
            "extra_arguments": attrs.list(attrs.string(), default = [], doc = """
                Only used during cross compilation.

                 This is the same as in `java_library()`.
            """),
            "annotation_processor_deps": attrs.list(attrs.dep(), default = []),
            "annotation_processor_params": attrs.list(attrs.string(), default = []),
            "annotation_processors": attrs.list(attrs.string(), default = []),
            "contacts": attrs.list(attrs.string(), default = []),
            "default_host_platform": attrs.option(attrs.configuration_label(), default = None),
            "exported_provided_deps": attrs.list(attrs.dep(), default = []),
            "javac": attrs.option(attrs.source(), default = None),
            "labels": attrs.list(attrs.string(), default = []),
            "licenses": attrs.list(attrs.source(), default = []),
            "manifest_file": attrs.option(attrs.source(), default = None),
            "maven_coords": attrs.option(attrs.string(), default = None),
            "never_mark_as_unused_dependency": attrs.option(attrs.bool(), default = None),
            "on_unused_dependencies": attrs.option(attrs.enum(UnusedDependenciesAction), default = None),
            "proguard_config": attrs.option(attrs.source(), default = None),
            "remove_classes": attrs.list(attrs.regex(), default = []),
            "required_for_source_only_abi": attrs.bool(default = False),
            "resources_root": attrs.option(attrs.source(), default = None),
            "runtime_deps": attrs.list(attrs.dep(), default = []),
            "source_abi_verification_mode": attrs.option(attrs.enum(SourceAbiVerificationMode), default = None),
            "source_only_abi_deps": attrs.list(attrs.dep(), default = []),
        }
    ) | jvm_common.plugins(),
)

groovy_test = prelude_rule(
    name = "groovy_test",
    docs = "",
    examples = None,
    further = None,
    attrs = (
        # @unsorted-dict-items
        {
            "annotation_processor_deps": attrs.list(attrs.dep(), default = []),
            "annotation_processor_params": attrs.list(attrs.string(), default = []),
            "annotation_processors": attrs.list(attrs.string(), default = []),
            "contacts": attrs.list(attrs.string(), default = []),
            "cxx_library_whitelist": attrs.list(attrs.dep(), default = []),
            "default_cxx_platform": attrs.option(attrs.string(), default = None),
            "default_host_platform": attrs.option(attrs.configuration_label(), default = None),
            "deps": attrs.list(attrs.dep(), default = []),
            "deps_query": attrs.option(attrs.query(), default = None),
            "env": attrs.dict(key = attrs.string(), value = attrs.arg(), sorted = False, default = {}),
            "exported_deps": attrs.list(attrs.dep(), default = []),
            "exported_provided_deps": attrs.list(attrs.dep(), default = []),
            "extra_arguments": attrs.list(attrs.string(), default = []),
            "extra_groovyc_arguments": attrs.list(attrs.string(), default = []),
            "fork_mode": attrs.enum(ForkMode, default = "none"),
            "java_version": attrs.option(attrs.string(), default = None),
            "javac": attrs.option(attrs.source(), default = None),
            "labels": attrs.list(attrs.string(), default = []),
            "licenses": attrs.list(attrs.source(), default = []),
            "manifest_file": attrs.option(attrs.source(), default = None),
            "maven_coords": attrs.option(attrs.string(), default = None),
            "never_mark_as_unused_dependency": attrs.option(attrs.bool(), default = None),
            "on_unused_dependencies": attrs.option(attrs.enum(UnusedDependenciesAction), default = None),
            "proguard_config": attrs.option(attrs.source(), default = None),
            "provided_deps": attrs.list(attrs.dep(), default = []),
            "remove_classes": attrs.list(attrs.regex(), default = []),
            "required_for_source_only_abi": attrs.bool(default = False),
            "resources": attrs.list(attrs.source(), default = []),
            "resources_root": attrs.option(attrs.source(), default = None),
            "run_test_separately": attrs.bool(default = False),
            "runtime_deps": attrs.list(attrs.dep(), default = []),
            "source": attrs.option(attrs.string(), default = None),
            "source_abi_verification_mode": attrs.option(attrs.enum(SourceAbiVerificationMode), default = None),
            "source_only_abi_deps": attrs.list(attrs.dep(), default = []),
            "srcs": attrs.list(attrs.source(), default = []),
            "std_err_log_level": attrs.option(attrs.one_of(attrs.enum(LogLevel), attrs.int()), default = None),
            "std_out_log_level": attrs.option(attrs.one_of(attrs.enum(LogLevel), attrs.int()), default = None),
            "target": attrs.option(attrs.string(), default = None),
            "test_case_timeout_ms": attrs.option(attrs.int(), default = None),
            "test_rule_timeout_ms": attrs.option(attrs.int(), default = None),
            "test_type": attrs.option(attrs.enum(TestType), default = None),
            "use_cxx_libraries": attrs.option(attrs.bool(), default = None),
            "use_dependency_order_classpath": attrs.option(attrs.bool(), default = None),
            "vm_args": attrs.list(attrs.arg(), default = []),
        }
    ) | jvm_common.plugins(),
)

groovy_rules = struct(
    groovy_library = groovy_library,
    groovy_test = groovy_test,
)
