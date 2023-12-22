// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

interface IV1Zapper {
    function zapIn(
        address tokenA,
        address tokenB,
        uint amountA,
        bool stable,
        uint minLpOut
    ) external;
}

interface ILpDepositor {
    function tokenForPool(address pool) external view returns (address);

    function deposit(address pool, uint amount) external;
}

contract neadTradeFeeHandler is
    Initializable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PROXY_ADMIN_ROLE = keccak256("PROXY_ADMIN");

    address public proxyAdmin;
    address public aggregator;
    address public nfpDepositor;

    EnumerableSetUpgradeable.AddressSet aggregatorApprovals;
    EnumerableSetUpgradeable.AddressSet tokenList;

    struct balanceData {
        address token;
        uint amount;
    }

    address constant neadRam = 0x40301951Af3f80b8C1744ca77E55111dd3c1dba1;
    address constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public V1Zapper;
    address public zapTo; // V1 pool
    address public tokenForPool; // ennead token for pool
    address public lpDepositor;
    address public treasury;

    EnumerableSetUpgradeable.AddressSet isV1ZapApproved;
    EnumerableSetUpgradeable.AddressSet isLpDepositorApproved;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _setter,
        address _operator,
        address _proxyAdmin
    ) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SETTER_ROLE, _setter);
        _grantRole(OPERATOR_ROLE, _operator);
        _grantRole(PROXY_ADMIN_ROLE, _proxyAdmin);
        _setRoleAdmin(PROXY_ADMIN_ROLE, PROXY_ADMIN_ROLE);
        proxyAdmin = _proxyAdmin;
    }

    function swapTokens(
        bytes calldata _data,
        address token
    ) external onlyRole(OPERATOR_ROLE) {
        if (!aggregatorApprovals.contains(token))
            IERC20Upgradeable(token).approve(aggregator, type(uint).max);
        (bool success, ) = aggregator.call(_data);
        require(success, "Swap fail");
        tokenList.add(token);
    }

    function notifyTokens(address token) external {
        require(msg.sender == nfpDepositor, "!depositor");
        tokenList.add(token);
    }

    function getAllTokens() external view returns (address[] memory tokens) {
        tokens = tokenList.values();
    }

    function getBalanceData()
        external
        view
        returns (balanceData[] memory bals)
    {
        address[] memory tokens = tokenList.values();
        uint len = tokens.length;
        bals = new balanceData[](len);

        for (uint i; i < len; ++i) {
            bals[i].token = tokens[i];
            bals[i].amount = IERC20Upgradeable(tokens[i]).balanceOf(
                address(this)
            );
        }
    }

    function withdrawTokens(
        address to,
        address token,
        uint amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20Upgradeable(token).transfer(to, amount);
    }

    /// @dev changing aggregators would need aggregator approvals to be reset
    function setAggregator(address _aggregator) external onlyRole(SETTER_ROLE) {
        aggregator = _aggregator;
    }

    function setNfpDepositor(
        address _nfpDepositor
    ) external onlyRole(SETTER_ROLE) {
        nfpDepositor = _nfpDepositor;
    }

    /// @dev sets aggregator approval for `tokens` to false, only do if changing aggregators
    function resetAggregatorApproval(
        address[] calldata tokens
    ) external onlyRole(SETTER_ROLE) {
        for (uint i; i < tokens.length; ++i) {
            aggregatorApprovals.remove(tokens[i]);
        }
    }

    function setV1Zapper(address _V1Zapper) external onlyRole(SETTER_ROLE) {
        V1Zapper = _V1Zapper;
    }

    function setZapTo(address pool) external onlyRole(SETTER_ROLE) {
        zapTo = pool;
        IERC20Upgradeable(pool).approve(lpDepositor, type(uint).max);
    }

    function setTokenForPool(
        address _tokenForPool
    ) external onlyRole(SETTER_ROLE) {
        tokenForPool = _tokenForPool;
    }

    function setLpDepositor(
        address _lpDepositor
    ) external onlyRole(SETTER_ROLE) {
        lpDepositor = _lpDepositor;
    }

    function setTreasury(address _treasury) external onlyRole(SETTER_ROLE) {
        treasury = _treasury;
    }

    /// @notice tokenA is token to zap
    /// @notice can only zap to zapTo
    function zapToken(
        address tokenA,
        address tokenB,
        bool stable
    ) external onlyRole(OPERATOR_ROLE) {
        uint bal = IERC20Upgradeable(tokenA).balanceOf(address(this));
        if (!isV1ZapApproved.contains(tokenA)) {
            IERC20Upgradeable(tokenA).approve(V1Zapper, type(uint).max);
            isV1ZapApproved.add(tokenA);
        }

        IV1Zapper(V1Zapper).zapIn(tokenA, tokenB, bal, stable, 0);
        if (!isLpDepositorApproved.contains(zapTo)) {
            IERC20Upgradeable(zapTo).approve(lpDepositor, type(uint).max);
        }

        bal = IERC20Upgradeable(zapTo).balanceOf(address(this));
        ILpDepositor(lpDepositor).deposit(zapTo, bal);
        IERC20Upgradeable(tokenForPool).transfer(treasury, bal);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(PROXY_ADMIN_ROLE) {}

    /// @dev grantRole already checks role, so no more additional checks are necessary
    function changeAdmin(address newAdmin) external {
        grantRole(PROXY_ADMIN_ROLE, newAdmin);
        renounceRole(PROXY_ADMIN_ROLE, proxyAdmin);
        proxyAdmin = newAdmin;
    }

    function setProxyRoleAdmin() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(PROXY_ADMIN_ROLE, PROXY_ADMIN_ROLE);
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}

