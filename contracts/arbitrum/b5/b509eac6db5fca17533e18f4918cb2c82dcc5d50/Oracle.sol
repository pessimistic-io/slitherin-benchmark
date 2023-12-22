// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IBaseOracle.sol";
import "./IOracle.sol";
import "./DefaultAccessControl.sol";
import "./CommonLibrary.sol";
import "./OracleRegistry.sol";

contract Oracle is IOracle, DefaultAccessControl {
    struct TokensOrder {
        address[] sortedTokens;
        uint32[] tokenIndexByDepth;
        uint32[] tokenDepthByIndex;
    }

    OracleRegistry public immutable oracleRegistry;

    address public constant USD = address(840);

    TokensOrder private _order;

    constructor(OracleRegistry registry, address admin) DefaultAccessControl(admin) {
        oracleRegistry = registry;
    }

    function tokensOrder() public view returns (address[] memory, uint32[] memory, uint32[] memory) {
        TokensOrder memory order = _order;
        return (order.sortedTokens, order.tokenIndexByDepth, order.tokenDepthByIndex);
    }

    function updateOrder(TokensOrder memory order) external {
        _requireAdmin();
        _order = order;
    }

    function _getSubTokens(
        address token,
        IBaseOracle.SecurityParams calldata requestedParams,
        uint256 requestedAmount
    ) private view returns (address[] memory subTokens, uint256[] memory subTokenAmounts) {
        (address oracle, IBaseOracle.SecurityParams memory params) = oracleRegistry.getOracle(token);
        if (requestedParams.parameters.length > 0) {
            params = requestedParams;
        }
        require(oracle != address(0));
        (subTokens, subTokenAmounts) = IBaseOracle(oracle).quote(token, requestedAmount, params);
    }

    function price(
        address[] calldata tokens,
        uint256[] calldata requestedTokenAmounts,
        IBaseOracle.SecurityParams[] calldata requestedTokensParameters,
        IBaseOracle.SecurityParams[] calldata allTokensParameters
    ) public view override returns (uint256) {
        TokensOrder memory order = _order;
        require(
            tokens.length == requestedTokenAmounts.length && allTokensParameters.length == order.sortedTokens.length,
            "Invalid length"
        );
        uint256[] memory tokenAmounts = new uint256[](order.sortedTokens.length);
        {
            for (uint32 i = 0; i < tokens.length; i++) {
                address token = tokens[i];
                {
                    uint32 index = CommonLibrary.binarySearch(order.sortedTokens, token);
                    if (index < type(uint32).max) {
                        tokenAmounts[index] += requestedTokenAmounts[i];
                        continue;
                    }
                }
                // cannot find token -> new token, depth = inf

                (address[] memory subTokens, uint256[] memory subTokenAmounts) = _getSubTokens(
                    token,
                    requestedTokensParameters[i],
                    requestedTokenAmounts[i]
                );

                for (uint256 j = 0; j < subTokens.length; j++) {
                    address subtoken = subTokens[j];
                    uint32 subTokenIndex = CommonLibrary.binarySearch(order.sortedTokens, subtoken);
                    require(subTokenIndex < order.sortedTokens.length, "Invalid state");
                    tokenAmounts[subTokenIndex] += subTokenAmounts[j];
                }
            }
        }
        for (uint32 depth = 0; depth + 1 < tokenAmounts.length; depth++) {
            uint32 tokenIndex = order.tokenIndexByDepth[depth];
            if (tokenAmounts[tokenIndex] == 0) continue;
            (address oracle, IBaseOracle.SecurityParams memory params) = oracleRegistry.getOracle(
                order.sortedTokens[tokenIndex]
            );
            if (allTokensParameters[tokenIndex].parameters.length > 0) {
                params = allTokensParameters[tokenIndex];
            }
            require(oracle != address(0), "Address zero");
            (address[] memory subTokens, uint256[] memory subTokenAmounts) = IBaseOracle(oracle).quote(
                order.sortedTokens[tokenIndex],
                tokenAmounts[tokenIndex],
                params
            );
            for (uint32 j = 0; j < subTokens.length; j++) {
                uint32 subTokenIndex = CommonLibrary.binarySearch(order.sortedTokens, subTokens[j]);
                require(subTokenIndex < type(uint32).max, "Token not found");
                require(depth < order.tokenDepthByIndex[subTokenIndex], "Cyclic dependency");
                tokenAmounts[subTokenIndex] += subTokenAmounts[j];
            }
        }
        return tokenAmounts[order.tokenIndexByDepth[order.tokenIndexByDepth.length - 1]];
    }

    function getTokenAmounts(
        address[] calldata tokens,
        address user
    ) public view override returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = ERC20(tokens[i]).balanceOf(user);
        }
    }
}

