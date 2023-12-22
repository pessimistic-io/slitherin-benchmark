// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./TransparentUpgradeableProxy.sol";
import "./ProxyAdmin.sol";
import "./AccessControl.sol";
import "./Initializable.sol";
import "./IHotpotFactory.sol";
import "./IHotpotToken.sol";
import "./IBondingCurve.sol";
import {GovernorLib} from "./GovernorLib.sol";
import "./IHook.sol";

contract HotpotTokenFactory is IHotpotFactory, Initializable, AccessControl {
    bytes32 public constant PLATFORM_ADMIN_ROLE = keccak256("PLATFORM_ADMIN");

    mapping(string => address) private _implementsMap;
    mapping(uint256 => address) private tokens;
    mapping(address => string) private tokensType;
    mapping(address => uint256) private upgradeTimelock;
    mapping(address => bytes) private upgradeList;
    mapping(address => bool) public whitelistHooks;
    mapping(address => address[]) public tokenHooks;

    uint256 private tokensLength;

    mapping(string => address) private _hotpotImplementMap;
    address private _platformAdmin;
    address private _platformTreasury;
    ProxyAdmin private _proxyAdmin;

    uint256 private constant MAX_PLATFORM_TAX_RATE = 100;
    uint256 private _platformMintTax;
    uint256 private _platformBurnTax;
    address private _route;

    modifier onlyProjectAdmin(address tokenAddr) {
        bytes32 projectAdminRole = IHotpotToken(tokenAddr).getProjectAdminRole();
        require(IHotpotToken(tokenAddr).hasRole(projectAdminRole, msg.sender), "not project admin");
        _;
    }

    receive() external payable {
        (bool success, ) = _platformTreasury.call{value: msg.value}("");
        require(success, "platform transfer failed");
    }

    fallback() external payable {}

    function initialize(address platformAdmin, address platformTreasury, address route) public initializer {
        _grantRole(PLATFORM_ADMIN_ROLE, platformAdmin);
        _platformAdmin = platformAdmin;
        _platformTreasury = platformTreasury;
        _route = route;
        _platformMintTax = 80;
        _platformBurnTax = 80;
        _proxyAdmin = new ProxyAdmin();
    }

    function deployToken(TokenInfo calldata token, uint256 mintfirstAmount) public payable {
        bytes memory call = abi.encodeWithSelector(
            IHotpotToken.initialize.selector,
            getBondingCurveImplement(token.bondingCurveType),
            token.name,
            token.symbol,
            token.metadata,
            token.projectAdmin,
            token.projectTreasury,
            token.projectMintTax,
            token.projectBurnTax,
            token.raisingTokenAddr,
            token.data,
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            getHotpotImplement(token.tokenType),
            address(_proxyAdmin),
            call
        );
        uint256 tokenId = tokensLength;
        tokens[tokensLength] = address(proxy);
        tokensLength++;
        tokensType[address(proxy)] = token.tokenType;
        if (mintfirstAmount > 0) {
            (uint256 minReceive, , , ) = IHotpotToken(address(proxy)).estimateMint(msg.value);
            if (token.raisingTokenAddr != address(0)) {
                IERC20(token.raisingTokenAddr).transferFrom(msg.sender, address(this), mintfirstAmount);
                IERC20(token.raisingTokenAddr).approve(address(proxy), mintfirstAmount);
            }
            IHotpotToken(address(proxy)).mint{value: token.raisingTokenAddr == address(0) ? mintfirstAmount : 0}(
                msg.sender,
                mintfirstAmount,
                minReceive
            );
        }
        emit LogTokenDeployed(token.tokenType, token.bondingCurveType, tokenId, address(proxy));
    }

    function createGovernorForToken(address proxyAddr, GovernorLib.GovInfo calldata govInfo) public {
        GovernorLib.createGovernorForToken(proxyAddr, govInfo);
    }

    function setPlatformTaxRate(uint256 platformMintTax, uint256 platformBurnTax) public onlyRole(PLATFORM_ADMIN_ROLE) {
        require(
            MAX_PLATFORM_TAX_RATE >= platformMintTax && platformMintTax >= 0,
            "SetTax:Platform Mint Tax Rate must between 0% to 1%"
        );
        require(
            MAX_PLATFORM_TAX_RATE >= platformBurnTax && platformBurnTax >= 0,
            "SetTax:Platform Burn Tax Rate must between 0% to 1%"
        );
        _platformMintTax = platformMintTax;
        _platformBurnTax = platformBurnTax;
        emit LogPlatformTaxChanged();
    }

    function getTaxRateOfPlatform() public view returns (uint256 platformMintTax, uint256 platformBurnTax) {
        return (_platformMintTax, _platformBurnTax);
    }

    function addBondingCurveImplement(address impl) public onlyRole(PLATFORM_ADMIN_ROLE) {
        require(impl != address(0), "invalid implement");
        string memory bondingCurveType = IBondingCurve(impl).BondingCurveType();
        require(bytes(bondingCurveType).length != bytes("").length, "bonding curve type error");
        require(_implementsMap[bondingCurveType] == address(0), "this type already exist");
        _implementsMap[bondingCurveType] = impl;
        emit LogBondingCurveTypeImplAdded(bondingCurveType, impl);
    }

    function getBondingCurveImplement(string calldata bondingCurveType) public view returns (address impl) {
        impl = _implementsMap[bondingCurveType];
        require(impl != address(0), "no such implement");
    }

    function updateHotpotImplement(string calldata tokenType, address impl) public onlyRole(PLATFORM_ADMIN_ROLE) {
        _hotpotImplementMap[tokenType] = impl;
        emit LogTokenTypeImplAdded(tokenType, impl);
    }

    function getHotpotImplement(string memory tokenType) public view returns (address impl) {
        impl = _hotpotImplementMap[tokenType];
        require(impl != address(0), "no such implement");
    }

    function getTokensLength() public view returns (uint256 len) {
        len = tokensLength;
    }

    function getToken(uint256 index) public view returns (address addr) {
        addr = tokens[index];
        require(addr != address(0), "no such token");
    }

    function getRoute() public view returns (address) {
        return _route;
    }

    function getPlatformAdmin() public view returns (address) {
        return _platformAdmin;
    }

    function getPlatformTreasury() public view returns (address) {
        return _platformTreasury;
    }

    function setRoute(address route) public onlyRole(PLATFORM_ADMIN_ROLE) {
        require(route != address(0), "Invalid Address");
        _route = route;
        emit LogRouteChanged(route);
    }

    function setPlatformAdmin(address newPlatformAdmin) public onlyRole(PLATFORM_ADMIN_ROLE) {
        require(newPlatformAdmin != address(0), "Invalid Address");
        _revokeRole(PLATFORM_ADMIN_ROLE, _platformAdmin);
        _grantRole(PLATFORM_ADMIN_ROLE, newPlatformAdmin);
        _platformAdmin = newPlatformAdmin;
        emit LogPlatformAdminChanged(newPlatformAdmin);
    }

    function setPlatformTreasury(address newPlatformTreasury) public onlyRole(PLATFORM_ADMIN_ROLE) {
        require(newPlatformTreasury != address(0), "Invalid Address");
        _platformTreasury = newPlatformTreasury;
        emit LogPlatformTreasuryChanged(newPlatformTreasury);
    }

    function declareDoomsday(address proxyAddress) external override onlyRole(PLATFORM_ADMIN_ROLE) {
        IHotpotToken(proxyAddress).declareDoomsday();
    }

    function pause(address proxyAddress) external override onlyRole(PLATFORM_ADMIN_ROLE) {
        IHotpotToken(proxyAddress).pause();
    }

    function unpause(address proxyAddress) external override onlyRole(PLATFORM_ADMIN_ROLE) {
        IHotpotToken(proxyAddress).unpause();
    }

    function requestUpgrade(address proxyAddress, bytes calldata data) external onlyRole(PLATFORM_ADMIN_ROLE) {
        string memory tokenType = tokensType[proxyAddress];
        address tokenImpl = getHotpotImplement(tokenType);
        require(
            tokenImpl != _proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(proxyAddress))),
            "Upgrade Failed: Same Implement"
        );
        upgradeTimelock[proxyAddress] = block.timestamp + 2 days;
        upgradeList[proxyAddress] = abi.encode(tokenImpl, data);
        emit LogTokenUpgradeRequested(proxyAddress, upgradeTimelock[proxyAddress], tokenImpl, msg.sender, data);
    }

    function rejectUpgrade(address proxyAddress, string calldata reason) external onlyProjectAdmin(proxyAddress) {
        require(upgradeTimelock[proxyAddress] != 0, "project have no upgrade");
        upgradeTimelock[proxyAddress] = 0;
        upgradeList[proxyAddress] = new bytes(0);
        emit LogTokenUpgradeRejected(proxyAddress, msg.sender, reason);
    }

    /**
     * @notice when the upgrade requested, admin can upgrade the implement of token after 2 days
     * @param proxyAddress the proxy address of token
     */
    function upgradeTokenImplement(address proxyAddress) external payable override onlyRole(PLATFORM_ADMIN_ROLE) {
        require(
            upgradeTimelock[proxyAddress] != 0 && upgradeTimelock[proxyAddress] <= block.timestamp,
            "Upgrade Failed: timelock"
        );
        (address impl, bytes memory data) = abi.decode(upgradeList[proxyAddress], (address, bytes));
        upgradeTimelock[proxyAddress] = 0;
        upgradeList[proxyAddress] = new bytes(0);
        _proxyAdmin.upgradeAndCall{value: msg.value}(TransparentUpgradeableProxy(payable(proxyAddress)), impl, data);
        emit LogTokenImplementUpgraded(proxyAddress, tokensType[proxyAddress], _implementsMap[tokensType[proxyAddress]]);
    }

    function setHook(address hook, bool flag) external override onlyRole(PLATFORM_ADMIN_ROLE) {
        whitelistHooks[hook] = flag;
    }

    function addHookForToken(address token, address hook, bytes calldata data) external override onlyProjectAdmin(token) {
        require(whitelistHooks[token], "not whitelist");
        tokenHooks[token].push(hook);
        IHook(hook).registerHook(token, data);
    }

    function updateHookForToken(
        address token,
        address[] calldata hooks,
        bytes[] calldata datas
    ) external override onlyProjectAdmin(token) {
        require(hooks.length == datas.length);
        tokenHooks[token] = hooks;
        for (uint256 i = 0; i < hooks.length; i++) {
            IHook(hooks[i]).registerHook(token, datas[i]);
        }
    }

    function removeHookForToken(address token, address hook) external override onlyProjectAdmin(token) {
        address[] memory hooks = tokenHooks[token];
        delete tokenHooks[token];
        for (uint256 i = 0; i < hooks.length; i++) {
            if (hook != hooks[i]) {
                tokenHooks[token].push(hooks[i]);
            } else {
                IHook(hook).unregisterHook(token);
            }
        }
    }

    function removeAllHookForToken(address token) external override onlyProjectAdmin(token) {
        address[] memory hooks = tokenHooks[token];
        for (uint256 i = 0; i < hooks.length; i++) {
            IHook(hooks[i]).unregisterHook(token);
        }
        delete tokenHooks[token];
    }

    function getTokenHooks(address token) external view override returns (address[] memory) {
        return tokenHooks[token];
    }
}

