// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./EnumerableSet.sol";

import "./DefaultAccessControl.sol";
import "./Oracle.sol";

import "./IBaseCollector.sol";

contract Collector is DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    error CollectorNotFound();

    struct Data {
        address collector;
        string name;
    }

    mapping(address => Data) public dataForVault;
    EnumerableSet.AddressSet private _supportedVaults;

    Oracle public oracle;
    address[] public tokens;
    bytes[] public securityParams;

    constructor(address owner) DefaultAccessControl(owner) {}

    function supportedVaults() public view returns (address[] memory) {
        return _supportedVaults.values();
    }

    function setData(address[] memory vaults, address[] memory collectors, string[] memory names) external {
        _requireAdmin();
        for (uint256 i = 0; i < vaults.length; i++) {
            dataForVault[vaults[i]] = Data({collector: collectors[i], name: names[i]});
            if (collectors[i] == address(0)) {
                _supportedVaults.remove(vaults[i]);
            } else {
                _supportedVaults.add(vaults[i]);
            }
        }
    }

    function updateOracle(Oracle oracle_, address[] memory tokens_, bytes[] memory securityParams_) external {
        _requireAdmin();
        oracle = oracle_;
        securityParams = securityParams_;
        tokens = tokens_;
    }

    function getPriceToUSDC(address token) public view returns (uint256 priceX96) {
        uint256[] memory tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokenAmounts[i] = 2 ** 96;
            }
        }
        priceX96 = oracle.quote(tokens, tokenAmounts, securityParams);
    }

    function collectAll(
        address[] memory operators,
        address user
    ) public view returns (IBaseCollector.Response[] memory responses, uint256[] memory balances) {
        address[] memory vaults = supportedVaults();
        IBaseCollector.Request[] memory requests = new IBaseCollector.Request[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            requests[i].vault = vaults[i];
            requests[i].user = user;
        }

        return collect(requests, operators);
    }

    function collectUserBalances(address[] memory users) public view returns (uint256[] memory balances) {
        balances = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            balances[i] = users[i].balance;
        }
    }

    function collect(
        IBaseCollector.Request[] memory requests,
        address[] memory users
    ) public view returns (IBaseCollector.Response[] memory responses, uint256[] memory balances) {
        balances = collectUserBalances(users);
        responses = new IBaseCollector.Response[](requests.length);

        uint256 blockNumber = block.number;
        uint256 blockTimestamp = block.timestamp;

        for (uint256 i = 0; i < requests.length; i++) {
            Data memory data = dataForVault[requests[i].vault];

            if (data.collector == address(0)) {
                revert CollectorNotFound();
            }
            address[] memory underlyingTokens;
            (responses[i], underlyingTokens) = IBaseCollector(data.collector).collect(
                requests[i].vault,
                requests[i].user
            );
            responses[i].blockNumber = blockNumber;
            responses[i].blockTimestamp = blockTimestamp;

            responses[i].pricesToUSDC = new uint256[](underlyingTokens.length);
            responses[i].decimals = new uint256[](underlyingTokens.length);
            responses[i].tokens = new address[](underlyingTokens.length);

            for (uint256 j = 0; j < underlyingTokens.length; j++) {
                address token = underlyingTokens[j];
                uint256 priceX96 = getPriceToUSDC(token);
                responses[i].pricesToUSDC[j] = priceX96;
                responses[i].tokens[j] = token;
                responses[i].decimals[j] = IERC20Metadata(token).decimals();
            }
            responses[i].name = data.name;
        }
    }
}

