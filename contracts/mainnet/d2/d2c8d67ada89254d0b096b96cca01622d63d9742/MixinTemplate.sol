// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./OwnableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./ProxyAdmin.sol";

contract MixinTemplate is
  OwnableUpgradeable,
  AccessControlEnumerableUpgradeable
{
  // TrustChain templates
  mapping(address => uint16) private _trustChainTemplateVersions;
  mapping(uint16 => address) private _trustChainTemplateImpls;
  uint16 public trustChainTemplateLatestVersion;

  // store proxy admin
  address public proxyAdminAddress;
  ProxyAdmin internal proxyAdmin;

  event TrustChainUpgraded(address trustChainAddress, uint16 version);

  function __MixinTemplate_init() internal onlyInitializing {
    require(proxyAdminAddress == address(0), "ALREADY_DEPLOYED");
    __Ownable_init();
    __AccessControlEnumerable_init();
    __AccessControl_init();
    _deployProxyAdmin();
  }

  /**
   * @dev Deploy the ProxyAdmin contract that will manage templates upgrades
   * This deploys an instance of ProxyAdmin used by publicTrustChain transparent proxies.
   */
  function _deployProxyAdmin() private returns (address) {
    proxyAdmin = new ProxyAdmin();
    proxyAdminAddress = address(proxyAdmin);
    return address(proxyAdmin);
  }

  /**
   * @dev Registers a new TrustChain template immplementation
   * The template is identified by a version number
   * Once registered, the template can be used to upgrade an existing PublicTrustChain
   */
  function addTrustChainTemplate(
    address impl,
    uint16 version
  ) public onlyOwner {
    _trustChainTemplateVersions[impl] = version;
    _trustChainTemplateImpls[version] = impl;

    if (trustChainTemplateLatestVersion < version) {
      trustChainTemplateLatestVersion = version;
    }

    // TODO emit TustChainTemplateAdded(impl, version);
  }

  /**
   * @dev Helper to get the version number of a template from his address
   */
  function trustChainTemplateVersions(
    address _impl
  ) external view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint16) {
    return _trustChainTemplateVersions[_impl];
  }

  /**
   * @dev Helper to get the address of a template based on its version number
   */
  function trustChainTemplateImpl(
    uint16 _version
  ) external view onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
    return _trustChainTemplateImpl(_version);
  }

  function _trustChainTemplateImpl(
    uint16 _version
  ) internal view returns (address) {
    return _trustChainTemplateImpls[_version];
  }

  /**
   * @dev Upgrade a TrustChain template implementation
   * @param trustChainAddress the address of the credential contract to be upgraded
   * @param version the version number of the template
   */
  function upgradeTrustChain(
    address payable trustChainAddress,
    uint16 version
  ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
    require(proxyAdminAddress != address(0), "MISSING_PROXY_ADMIN");

    // check version
    MixinTemplate trustChain = MixinTemplate(trustChainAddress);
    uint16 currentVersion = trustChain.trustChainTemplateLatestVersion();
    require(version > currentVersion, "VERISON_TOO_LOW");

    // make our upgrade
    address impl = _trustChainTemplateImpls[version];
    require(impl != address(0), "MISSING_TEMPLATE");

    TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(
      trustChainAddress
    );
    proxyAdmin.upgrade(proxy, impl);
    trustChain.addTrustChainTemplate(impl, version);

    emit TrustChainUpgraded(trustChainAddress, version);
    return trustChainAddress;
  }

  function supportsInterface(
    bytes4 interfaceId
  )
    public
    view
    virtual
    override(AccessControlEnumerableUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}

