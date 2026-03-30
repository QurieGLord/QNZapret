Name:           nzapret-desktop
Version:        1.0.0+1
Release:        1%{?dist}
Summary:        Linux desktop controller for bundled nfqws strategy and nftables
License:        LicenseRef-Unknown
%global repo_url %{?source_repo_url}%{!?source_repo_url:https://github.com/REPLACE_ME/REPLACE_ME}
URL:            %{repo_url}

%global source_archive %{name}-%{version}-source.tar.gz
Source0:        %{?source_url}%{!?source_url:%{repo_url}/releases/download/v%{version}/%{source_archive}}

BuildRequires:  clang
BuildRequires:  cmake
BuildRequires:  flutter
BuildRequires:  gtk3-devel
BuildRequires:  ninja-build
BuildRequires:  pkgconf-pkg-config
BuildRequires:  util-linux-devel

Requires:       gtk3
Requires:       nftables

%description
Flutter desktop application for Linux that bundles an nfqws strategy,
manages nftables queue rules, and provides runtime logs and privileged
start/stop controls through pkexec when available.

%prep
%autosetup -n %{name}-%{version}

%build
flutter pub get
./build-linux.sh

%install
install -dm755 %{buildroot}/opt/%{name}
cp -a build/linux/x64/release/bundle/. %{buildroot}/opt/%{name}/

install -dm755 %{buildroot}%{_bindir}
ln -s /opt/%{name}/nzapret_desktop %{buildroot}%{_bindir}/%{name}

install -Dm644 packaging/linux/nzapret-desktop.desktop \
  %{buildroot}%{_datadir}/applications/%{name}.desktop
install -Dm644 assets/branding/nzapret-desktop.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg
install -Dm644 README.md \
  %{buildroot}%{_datadir}/doc/%{name}/README.md

%files
/opt/%{name}
%{_bindir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg
%doc %{_datadir}/doc/%{name}/README.md

%changelog
* Wed Mar 26 2026 NZapret Desktop Maintainers <noreply@localhost> - 1.0.0+1-1
- Initial Linux desktop packaging
