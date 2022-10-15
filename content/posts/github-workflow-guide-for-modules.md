+++
title = "A Github Workflow guide for CPAN modules"
date = 2022-10-16T21:00:00+01:00
images = []
tags = []
categories = ["coding"]
+++

GitHub Actions give you [Continuous integration](https://en.wikipedia.org/wiki/Continuous_integration) for free.
That means you can have your module's unit tests run for you on various different versions of Perl, on Linux, MacOS and Windows,
whenever you push a commit or someone opens a pull request. This is very useful to make sure contributions don't break your code,
or to enforce certain coding guidelines such as requiring code to follow a specific [perltidyrc](https://metacpan.org/dist/Perl-Tidy/view/bin/perltidy#Using-a-.perltidyrc-command-file).

Introduction
===

Before you start writing your own workflows, you might want to have a quick look at [the official documentation](https://docs.github.com/en/actions)
for Github Actions. The [quickstart guide](https://docs.github.com/en/actions/quickstart) offers a good overview.

A [_workflow_](https://docs.github.com/en/actions/using-workflows/about-workflows) is defined in a _workflow file_, which is a YAML file in your `.github/workflows` directory. You can have several of these, they just have to have unique names.
A workflow contains one or more [_jobs_](https://docs.github.com/en/actions/using-jobs/using-jobs-in-a-workflow). Each job gets run by a runner, and will be executed within its own container. Jobs can depend on other jobs, so you can do something like this:

{{< mermaid >}}
flowchart LR
A[Build the module] --> B[Test the module]
{{</ mermaid >}}


Jobs can be defined one at a time, or in [a _matrix_](https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs). This is a bit like a loop. You can define lists of variables, such as the operating system and the Perl version,
and it will spawn variations of the job for each combination.

{{< mermaid >}}
flowchart LR
A[Build] --> B1[Test on Linux with Perl 5.8]
A --> B2[Test on Linux with Perl 5.36]
A --> B3[Test on Windows with Perl 5.8]
A --> B4[Test on Windows with Perl 5.36]
{{</ mermaid >}}

A job consists of several steps, which are called _actions_. This is where the real work happens. Github provides some of these out of the box, such as [checking out code from your repository](https://github.com/marketplace/actions/checkout), [storing](https://github.com/marketplace/actions/upload-a-build-artifact) and [retrieving](https://github.com/marketplace/actions/download-a-build-artifact) a build artifact, or running shell commands. It is also possible to add tags or comments to PRs, or to close them automatically.

Using Perl-specific workflow tools
===

There are various tools specifically for Perl that people in the community have built. These are actively maintained and will make your life easier.

Let's jump right in with a complex example. This is [the current workflow for the URI module](https://github.com/libwww-perl/URI/blob/4a7a7294eb9b9b2416b3dd491227e4a8dcb45e1a/.github/workflows/dzil-build-and-test.yml), which I've included in full below. We will go through the whole thing step by step.

```yaml
---
name: dzil build and test

on:
  push:
    branches:
      - "*"
  pull_request:
    branches:
      - "*"
  schedule:
    - cron: "15 4 * * 0" # Every Sunday morning
  workflow_dispatch:

jobs:
  build-job:
    name: Build distribution
    runs-on: ubuntu-20.04
    container:
      image: perldocker/perl-tester:5.34
    steps:
      - uses: actions/checkout@v3
      - name: Run Tests
        env:
          AUTHOR_TESTING: 1
          AUTOMATED_TESTING: 1
          EXTENDED_TESTING: 1
          RELEASE_TESTING: 1
        run: auto-build-and-test-dist
      - uses: actions/upload-artifact@v3
        with:
          name: build_dir
          path: build_dir
        if: ${{ github.actor != 'nektos/act' }}
  coverage-job:
    needs: build-job
    runs-on: ubuntu-20.04
    container:
      image: perldocker/perl-tester:5.34
    steps:
      - uses: actions/checkout@v3 # codecov wants to be inside a Git repository
      - uses: actions/download-artifact@v3
        with:
          name: build_dir
          path: .
      - name: Install deps and test
        run: cpan-install-dist-deps && test-dist
        env:
          CODECOV_TOKEN: ${{secrets.CODECOV_TOKEN}}
  test-job:
    needs: build-job
    strategy:
      fail-fast: true
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        distribution: [default, strawberry]
        perl-version:
          - "5.8"
          - "5.10"
          - "5.12"
          - "5.14"
          - "5.16"
          - "5.18"
          - "5.20"
          - "5.22"
          - "5.24"
          - "5.26"
          - "5.28"
          - "5.30"
          - "5.32"
          - "5.34"
          - "5.36"
        exclude:
          - { os: windows-latest, distribution: default }
          - { os: macos-latest,   distribution: strawberry }
          - { os: ubuntu-latest,  distribution: strawberry }
          - { distribution: strawberry, perl-version: "5.8" }
          - { distribution: strawberry, perl-version: "5.10" }
          - { distribution: strawberry, perl-version: "5.12" }
          - { distribution: strawberry, perl-version: "5.34" }
          - { distribution: strawberry, perl-version: "5.36" }
    runs-on: ${{ matrix.os }}
    name:  on ${{ matrix.os }} perl ${{ matrix.perl-version }}
    steps:
      - name: set up perl
        uses: shogo82148/actions-setup-perl@v1
        with:
          perl-version: ${{ matrix.perl-version }}
          distribution: ${{ matrix.distribution }}
      - uses: actions/download-artifact@v3
        with:
          name: build_dir
          path: .
      - name: install deps using cpm
        uses: perl-actions/install-with-cpm@v1
        with:
          cpanfile: "cpanfile"
          args: "--with-suggests --with-recommends --with-test"
      - run: prove -lr t
        env:
          AUTHOR_TESTING: 0
          RELEASE_TESTING: 0
```

You can see the output of this workflow [here](https://github.com/libwww-perl/URI/actions/runs/3255037218) (if the output has been removed after some time, you can pick another one [in the actions tab on github](https://github.com/libwww-perl/URI/actions)). The diagram for this looks a bit like the following (simplified).

{{< mermaid >}}
flowchart LR
A[Build] --> Coverage
subgraph Test
  direction LR
  t1[on ubuntu-latest perl 5.8]
  t2[on ubuntu-latest perl 5.10]
  t3[...]
  t4[on ubuntu-latest perl 5.36]
  t5[on macos-latest perl 5.10]
  t6[...]
  t7[on macos-latest perl 5.36]
  t8[on windows-latest perl 5.14]
  t9[...]
  t10[on windows-latest perl 5.32]
end
A --> Test
{{</ mermaid >}}

Workflow basics
---

Let's run through step by step.

```yaml
name: dzil build and test
```

You have to set the name of your workflow. If you have several, this is how you distinguish them. One reason to have more than one workflow would be to build documentation that gets stored into a different branch to be hosted [on github pages](https://pages.github.com/), much like [the (only) workflow for this blog](https://github.com/simbabque/simbabque.github.io/blob/master/.github/workflows/gh-pages.yml).

```yaml
on:
  push:
    branches:
      - "*"
  pull_request:
    branches:
      - "*"
  schedule:
    - cron: "15 4 * * 0" # Every Sunday morning
  workflow_dispatch:
```

The `on` key controls when a workflow gets triggered. The options we've used here mean:

- run every time someone pushes to any branch in the repository (this is code you or your collaborators write),
- someone opens a pull request (also when they push or force push more code to their PR's branch),
- automatically as a cronjob,
- or with `workflow_dispatch` when you click the button to run it against a branch of your choosing.

The `schedule` makes sense if you want to rebuild something automatically, such as documentation, a blog or a static site, or if your tests rely on external websites that might go away. In most cases you probably do not want to use it. Dave Cross' website [Planet Perl](https://perl.theplanetarium.org/) heavily uses this feature to aggregate Perl blog posts from around the web several times a day.

```yaml
jobs:
```

The build job
---

Next we have the `jobs`. This workflow defines three different ones, as shown above in the diagram. The first one is for building the distribution. This is not so much about running the tests, but about building the module once, so that it can be used in subsequent tests on different platforms. That way we can save time on complicated build processes.

```yaml
jobs:
  build-job:
    name: Build distribution
    runs-on: ubuntu-20.04
    container:
      image: perldocker/perl-tester:5.34
    steps:
      - uses: actions/checkout@v3
      - name: Run Tests
        env:
          AUTHOR_TESTING: 1
          AUTOMATED_TESTING: 1
          EXTENDED_TESTING: 1
          RELEASE_TESTING: 1
        run: auto-build-and-test-dist
      - uses: actions/upload-artifact@v3
        with:
          name: build_dir
          path: build_dir
        if: ${{ github.actor != 'nektos/act' }}
```

The build job in our example runs on a specific Ubuntu version, on a custom Docker container named [perldocker](https://github.com/Perl/docker-perl-tester). It runs a specific Perl version that you chose in the `image` (this one uses 5.34), as well as the OS you set in the `runs-on` key. The container comes with a lot of different testing modules, CPAN clients such as [cpanm](https://metacpan.org/dist/App-cpanminus/view/lib/App/cpanminus/fatscript.pm) and [cpm](https://metacpan.org/dist/App-cpm/view/script/cpm) as well as spelling dictionaries and other useful stuff. This allows you to run most Perl related builds and tests pretty much out of the box, and cuts down on run time for individual jobs. The container is maintained by a group of volunteers from the Perl community, and lives in the same Github organisation as the Perl source code itself.

Once the container is set up, a number of steps are performed. The [`actions/checkout@v3`](https://github.com/marketplace/actions/checkout) action gets your code from the GitHub repository the action is associated with, and puts it into a local directory that becomes the working directory for the rest of the run. For example, if the workflow is running for a pull request, it will get the code from there.

The second step has more details, as it's not using a predefined action. A number of environment variables such as `AUTHOR_TESTING` and `RELEASE_TESTING` are set, before one of the scripts that come bundled with the Docker container are run. The `auto-build-and-test-dist` script will install all build, test and runtime dependencies, build the distribution from source and run tests against it. The aforementioned environment variables are used by various tests that are included in the Dist::Zilla configuration of the module we are using as an example here. The `auto-build-and-test-dist` script is bundled with the Perl Docker container, but has its own dedicated repository called [perl-actions/ci-perl-tester-helpers](https://github.com/perl-actions/ci-perl-tester-helpers). At the time of writing (October 2022) it supports distributions using [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla), [Minilla](https://metacpan.org/pod/Minilla) and [Module::Build](https://metacpan.org/pod/Module::Build).

The final step is another official action provided by GitHub [that stores a build artifact](https://github.com/marketplace/actions/upload-a-build-artifact) from one job so that it can be used by subsequent jobs in the same workflow. It needs to be given a `name` (think a cache key) and `path` to the file to store as its arguments, which are typically passed into actions using the `with` key. The `if` key allows a step to be run conditionally. In this case, a variable inside the runner is evaluated using `${{ ... }}`. We're checking whether the thing running this workflow is [a tool called `act`](https://github.com/nektos/act) (not the YAPC website). It allows you to test workflows locally on your computer without pushing lots of commits or force-pushing changes every time you make a change to the workflow file. It is handy, but you don't need this condition unless you plan to use `act`.

This brings us to the end of the build job. We now have a distribution stored and ready to be used in the subsequent jobs.

The coverage job
---

```yaml
  coverage-job:
    needs: build-job
    runs-on: ubuntu-20.04
    container:
      image: perldocker/perl-tester:5.34
    steps:
      - uses: actions/checkout@v3 # codecov wants to be inside a Git repository
      - uses: actions/download-artifact@v3
        with:
          name: build_dir
          path: .
      - name: Install deps and test
        run: cpan-install-dist-deps && test-dist
        env:
          CODECOV_TOKEN: ${{secrets.CODECOV_TOKEN}}
```

Although we're going to run a whole array of tests on different platforms later on in the workflow file, we don't want to collect test coverage data for all of them. Instead, we have defined a dedicated test run just to collect coverage data using [codecov.io](https://about.codecov.io/), which is free for Open Source projects. You need to create an account, which you can conveniently do with your GitHub login, and you also need to sync your repositories and enable them inside of codecov. You will be given a token, which you need to store in your GitHub repository's settings under Secrets inside Actions. In this example, we've named it `CODECOV_TOKEN`.

The job again runs on the Perl Docker container, and we've opted for Perl 5.34. Because we want to run this after the build job has finished, we set the `needs` key to the name of that job.

Codecov has a bit of an oddity in that it needs to be inside a git repository, so we run a checkout, although we're just going to run the tests on the distribution built in the previous job. This is where the artifact comes in, which we now [retrieve using another predefined action](https://github.com/marketplace/actions/download-a-build-artifact), again telling it the `name` and the `path` to put it in.

In the third step, we run two commands that both come with the Perl Docker container as part of the CI helpers repository.

`cpan-install-dist-deps` will install the distribution's dependencies into this container. We need to do that again because every job runs on a freshly spawned container, completely isolated from all the other jobs. The install script uses `cpm` to install dependencies. At the time of writing, it needs either [a `cpanfile`](https://metacpan.org/dist/Module-CPANfile/view/lib/cpanfile.pod) to be present, which is a limitation of `cpm`, or for the distribution to be built using Module::Build.

Once that has finishes successfully, the `test-dist` script is run, which will execute tests. It looks for various environment variables, and will enable different types of tests depending on which ones are present. If it finds the `CODECOV_TOKEN` environment variable, it will use [Devel::Cover](https://metacpan.org/pod/Devel::Cover) to capture test coverage data and report it to [codecov.io](https://about.codecov.io/) using [Devel::Cover::Report::Codecov](https://metacpan.org/pod/Devel::Cover::Report::Codecov). Note that this also works for [coveralls.io](https://coveralls.io/), which is a similar service that is also free for Open Source Software.

Lots of test jobs
---

```yaml
 test-job:
    needs: build-job
    strategy:
      fail-fast: true
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        distribution: [default, strawberry]
        perl-version:
          - "5.8"
          - "5.10"
          - "5.12"
          - "5.14"
          - "5.16"
          - "5.18"
          - "5.20"
          - "5.22"
          - "5.24"
          - "5.26"
          - "5.28"
          - "5.30"
          - "5.32"
          - "5.34"
          - "5.36"
        exclude:
          - { os: windows-latest, distribution: default }
          - { os: macos-latest,   distribution: strawberry }
          - { os: ubuntu-latest,  distribution: strawberry }
          - { distribution: strawberry, perl-version: "5.8" }
          - { distribution: strawberry, perl-version: "5.10" }
          - { distribution: strawberry, perl-version: "5.12" }
          - { distribution: strawberry, perl-version: "5.34" }
          - { distribution: strawberry, perl-version: "5.36" }
    runs-on: ${{ matrix.os }}
    name:  on ${{ matrix.os }} perl ${{ matrix.perl-version }}
    steps:
      - name: set up perl
        uses: shogo82148/actions-setup-perl@v1
        with:
          perl-version: ${{ matrix.perl-version }}
          distribution: ${{ matrix.distribution }}
      - uses: actions/download-artifact@v3
        with:
          name: build_dir
          path: .
      - name: install deps using cpm
        uses: perl-actions/install-with-cpm@v1
        with:
          cpanfile: "cpanfile"
          args: "--with-suggests --with-recommends --with-test"
      - run: prove -lr t
        env:
          AUTHOR_TESTING: 0
          RELEASE_TESTING: 0
```

The final part of the workflow file describes the big matrix test job. This short description of environment combinations will spawn a lot of different jobs that all run the same tests, enabling you to see very quickly whether changes to your code break on particular Perl versions, which is great for maintaining backwards compatibility, or to test something on an operating system you cannot run the tests on locally. The description looks mildly intimidating, but it is actually quite straight-forward.

Just like the coverage job, each of these jobs depends on the build job, as we will again use the build artifact.

The `strategy` key is used [to define the `matrix`](https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs). Each key holding an array of values inside this `matrix` is completely made up by us. We want to test across three different operating systems, Perl distribution types and Perl versions. The jobs will be combinations of these values. Because not all combinations make sense, some are `excluded`. As you can see, we have listed all Perl stable versions (those are the ones with even numbers after the 5) going back to 5.08 and including the most recent one at the time of writing, 5.36.

We need to exclude combinations that make no sense:

- any combination with Windows and the default distribution,
- both Mac OS and Linux with [Strawberry Perl](https://strawberryperl.com/), which is for Windows,
- Perl versions for which there is no Strawberry release.

The `fail-fast` key in the `strategy` makes the remaining jobs that have not run yet fail if one of the running ones fails. This saves resources and produces a failed test result faster.

You will notice that these jobs are not going to run on the Perl Docker container. Instead they use GitHub's official standard containers, which explains the values for the `os` matrix key. We don't need any special build or test tools here, but rather want to install our own specific Perl versions for each job. The `name` is a combination of the matrix values, so we can easily identify which job is for which environment.

The first step for each of these jobs is to set up a Perl environment. We use the community action [shogo82148/actions-setup-perl](https://github.com/marketplace/actions/setup-perl-environment) written by ICHINOSE Shogo. It takes the `perl-version` and `distribution` arguments which we have defined in our matrix. Each job will get a combination of these, accessed through the `matrix.perl-version` and `matrix.distribution` variables. The action will install the correct Perl version for us to use. It does that by downloading an archive with the pre-compiled version for the correct operating system.

Once that is done, we download our build artifact as before, so we can get testing.

In order to do that, we first have to install dependencies again. We use the community action [perl-actions/install-with-cpm](https://github.com/marketplace/actions/install-with-cpm) for that, which is provided and maintained by the same group of volunteers as the CI tools we used inside of the Perl Docker container above. There is also a [perl-actions/install-with-cpanm](https://github.com/marketplace/actions/install-with-cpanm) version that uses `cpanm` instead of `cpm`, which makes sense if you do not have a `cpanfile` in your distribution, as `cpm` does not know how else to retrieve dependencies, but `cpanm` does. We're telling `cpm` in the `args` that it should please install dependencies listed for the `test` phase, as well as all suggested and recommended modules. This will help get as complete a test result as possible.

Finally we `run` [the `prove` command](https://metacpan.org/dist/Test-Harness/view/bin/prove), telling it to recurse down into the `t/` directory to get all normal tests. We disable the `AUTHOR_TESTING` and `RELEASE_TESTING` environment variables, because we are only interested in whether our module works on this specific environment once it has reached a user. They're not building it, they just want to run it.

Conclusion
===
You should now have a good idea what a well structured workflow could look like. You can use this as a template, copy it exactly, or build upon it.

Also keep in mind that the Perl-specific tools are a work in progress, and are written by the community. As such they support the types of distributions that they have needed to support so far. Most of this is just Perl and Shell code, and you are more than welcome to add specific support for other distribution builds or CPAN clients if you need them and do not want to rely on a bunch of individual `run` steps in your workflows.
