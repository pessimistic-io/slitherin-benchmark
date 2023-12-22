// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _setter, address _operator) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SETTER_ROLE, _setter);
        _grantRole(OPERATOR_ROLE, _operator);
    }

    function swapTokens(
        bytes calldata _data,
        address token
    ) external onlyRole(OPERATOR_ROLE) {
        if (!aggregatorApprovals.contains(token))
            IERC20Upgradeable(token).approve(aggregator, type(uint).max);
        (bool success, ) = aggregator.call(_data);
        require(success, "Swap fail");
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

    function setNfpDepositor(address _nfpDepositor) external onlyRole(SETTER_ROLE) {
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

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(PROXY_ADMIN_ROLE) {}

    /// @dev grantRole already checks role, so no more additional checks are necessary
    function changeAdmin(address newAdmin) external {
        grantRole(PROXY_ADMIN_ROLE, newAdmin);
        renounceRole(PROXY_ADMIN_ROLE, proxyAdmin);
        proxyAdmin = newAdmin;
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}

