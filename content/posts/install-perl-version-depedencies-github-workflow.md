+++
title = "Installing Perl dependencies based on your Perl version in Github Actions"
date = 2022-06-23T15:00:00+01:00
images = []
tags = []
categories = ["coding"]
+++

[Github Actions](https://github.com/features/actions) are great for running tests, especially to check if pull requests are breaking your build. You can easily
set up jobs for different operating systems and Perl version using the excellent tooling already available for Perl. I will
link some of these in the course of this post.

At work I ran into an issue where I had to temporarily overwrite the value behind an accessor in a Catalyst Context object (`$c`).
Think `local $foo->{bar}`, but for `$foo->bar`. There is no built-in way of doing that, so I made a module that is now on CPAN.
It's called [MooseX::LocalAttribute](https://metacpan.org/pod/MooseX::LocalAttribute), but it works with all kinds of Perl objects, not just with Moose.

I included tests for all the object creation modules I could think of off the top of my head. There are quite a lot. While I think
that there are probably not many people who use [Mo](https://metacpan.org/pod/Mo) in production, [Moose](https://metacpan.org/pod/Moose)
and [Moo](https://metacpan.org/pod/Moo) are of course much more prevalent.

But there is another one that's quite popular now to help quickly make objects: [Mojolicious](https://metacpan.org/pod/Mojolicious).
It includes [Mojo::Base](https://metacpan.org/pod/Mojo::Base), which gives you
a very simple version of `has`. Internally it's also just a blessed hash reference with accessors, just like a Moo object. So of course
I wanted to support it.

That decision made me run into a problem with my test suite, which is basically the same set of test run for every type of object creation
module that is installed. And of course my Github Action should run all of them, on as many Perl versions as possible. But the folks at Mojolicious
are very forward-thinking. At the time of writing, the lowest supported Perl version for Mojolicious is 5.16. But I want my module to work on
Perl 5.08, as it doesn't do anything modern at all. And Mojolicious is just a testing dependency for me. I am using [Test::Requires](https://metacpan.org/pod/Test::Requires),
so if one of the modules I want to test against is not installed, that test file simply skips.

A modern Perl module distribution typicall defines its dependencies in a [cpanfile](https://metacpan.org/dist/Module-CPANfile/view/lib/cpanfile.pod).
In my case, this [gets picked up by Dist::Zilla and turned into the META.json file](https://metacpan.org/pod/Dist::Zilla::Plugin::Prereqs::FromCPANfile).
You can specify different phases such as `develop`, `test`, `build` and `runtime`, as well as how badly
your module needs a particular module. The default is `requires`, which means you have to have it, but it can also `recommends` or `suggests` things
that you might want to install. More details on this can be found in [CPAN::Meta::Spec](https://metacpan.org/pod/CPAN::Meta::Spec#Prereq-Spec).

I started out listing all of the things I could test against as `recommends`. My cpanfile looked like this.

```perl
on 'runtime' => sub {
    requires 'perl' => '5.008';
    requires 'Exporter';
    requires 'Scope::Guard';
};

on 'test' => sub {
    requires 'FindBin';
    requires 'Test::Exception';
    requires 'Test::More';
    requires 'Test::Requires';
    recommends 'Moose';
    recommends 'Moo';
    recommends 'Mo';
    recommends 'Mouse';
    recommends 'Class::Accessor';
    recommends 'Mojolicious';
};
```

And in my Github Action definition file, which is written in YAML and lives in the `.github/workflows` folder, I had a matrix of different Perl versions
set up for each operating system. That makes three different jobs with a list of Perl versions to test against, resulting in a lot of jobs that would
get run whenever a new commit or PR gets pushed. Here's a simplified extract of it, showing most of the test job for Ubuntu. There are two more similar
ones for Mac and Windows.

```yml
  ubuntu-test-job:
    needs: build-job
    runs-on: "ubuntu-20.04"
    strategy:
      fail-fast: true
      matrix:
        os: [ubuntu-20.04]
        perl-version:
          - "5.8"
          - "5.10"
          - "5.12"
          # ...
          - "5.32"
          - "5.34"
          - "5.36"
    name: perl ${{ matrix.perl-version }} on ${{ matrix.os }}
    steps:
      - name: set up perl
        uses: shogo82148/actions-setup-perl@v1
        with:
          perl-version: ${{ matrix.perl-version }}
      - uses: actions/download-artifact@v2
        with:
          name: build_dir
          path: .
      - name: install deps using cpm
        uses: perl-actions/install-with-cpm@v1
        with:
          cpanfile: "cpanfile"
          args: "--with-suggests --with-recommends --with-test"
      - run: prove -lr t
```

I want the tests to run on all stable Perl releases starting at Perl 5.8, and all the way through to the current one, which is 5.36 at
the time of writing. The job depends on another job that has already run, which built a release. It downloads that release, unpacks it,
and then installs dependencies using [`cpm`](https://metacpan.org/dist/App-cpm/view/script/cpm) via
[this handy action](https://github.com/marketplace/actions/install-with-cpm), including all of the suggested and recommended modules.

And that is where the problem arises. Mojolicious cannot be installed on Perls lower than 5.16, so the job called _install deps using cpm_
fails, which means that whole run goes red.

But I still want to be able to test against all of the other modules on Perls 5.8, 5.10, 5.12 and 5.14. My test suite allows that. If
it cannot load Mojolicious, it'll just skip that test. So I needed to find a way to not install Mojolicious on these versions. But I didn't
want to list it explicitly in the workflow file. It should still get the dependencies dynamically from the cpanfile, and of course that
must not mess with a user installing my module.

The solution seems fairly obvious once I had found it. It's possible to make individual steps of a job only execute
[`if` a condition is met](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idif). You can do
something like this:

```yml
- name: install deps using cpm
  if: matrix.perl-version == 5.14
  uses: perl-actions/install-with-cpm@v1
  with:
    cpanfile: "cpanfile"
    args: "--with-suggests --with-recommends --with-test"
```

But we also need a way to have Mojolicious be recognised as a special case. I did that by changing it from `recommends` to `suggests` in
my cpanfile, which make it less required. Most people will not install these soft requirements anyway, and especially not for test, so we
can safely do that.

```perl
on 'test' => sub {
    requires 'FindBin';
    requires 'Test::Exception';
    requires 'Test::More';
    requires 'Test::Requires';
    recommends 'Moose';
    recommends 'Moo';
    recommends 'Mo';
    recommends 'Mouse';
    recommends 'Class::Accessor';
    suggest 'Mojolicious';
};
```

We can also tell `cpm` that we explicitly want to not install a particular type of dependency.

```yml
args: "--without-suggests --with-recommends --with-test"
```

So now we need to tie this together. We can set up two different steps in the workflow, and only one will be executed.

```yml
- name: install deps using cpm - with Mojolicious
  if: matrix.perl-version >= "5.16"
  uses: perl-actions/install-with-cpm@v1
  with:
    cpanfile: "cpanfile"
    args: "--without-suggests --with-recommends --with-test"
- name: install deps using cpm - without Mojolicious
  if: matrix.perl-version < "5.16"
  uses: perl-actions/install-with-cpm@v1
  with:
    cpanfile: "cpanfile"
    args: "--with-suggests --with-recommends --with-test"
```

This looks great. But it doesn't work. [The action we are using to set up Perl](https://github.com/marketplace/actions/setup-perl-environment)
needs the version numbers to be actual numbers, so `5.8` is bigger than `5.10` and `5.36`. That's a problem,
because it will still install it for Perl 5.8, and that run will fail. So let's be more specific.

```yml
- name: install deps using cpm - with Mojolicious
  if: matrix.perl-version >= "5.16" && matrix.perl-version != "5.8"
  uses: perl-actions/install-with-cpm@v1
  with:
    cpanfile: "cpanfile"
    args: "--without-suggests --with-recommends --with-test"
- name: install deps using cpm - without Mojolicious
  if: matrix.perl-version < "5.16" || matrix.perl-version == "5.8"
  uses: perl-actions/install-with-cpm@v1
  with:
    cpanfile: "cpanfile"
    args: "--with-suggests --with-recommends --with-test"
```

This works. It's great, but if Mojolicious bump their Perl dependency to 5.18, we'll have to change this six times (twice for each OS). Can we make
it more dynamic?

We can set an environment variable in the workflow at the very top. It will be available as `env.MOJO_REQUIRED_VERSION` in all of the jobs.

```yml
env:
  MOJO_REQUIRED_VERSION: "5.16" # Bump this if Mojolicious increases their minimum Perl version
jobs:
  # ...
  ubuntu-test-job:
    # ...
```

Now we can refer to this variable throughout the jobs. This will repeat several times in the workflow file.

```yml
- name: install deps using cpm - with Mojolicious
  if: matrix.perl-version >= env.MOJO_REQUIRED_VERSION && matrix.perl-version != '5.8'
  uses: perl-actions/install-with-cpm@v1
  with:
    cpanfile: "cpanfile"
    args: "--with-suggests --with-recommends --with-test"
- name: install deps using cpm - without Mojolicious
  if: matrix.perl-version < env.MOJO_REQUIRED_VERSION || matrix.perl-version == '5.8'
  uses: perl-actions/install-with-cpm@v1
  with:
    cpanfile: "cpanfile"
    args: "--without-suggests --with-recommends --with-test"
```

In conclusion, while YAML development isn't going to be my favourite next role, I can still apply some programming paradigms to these config files.

