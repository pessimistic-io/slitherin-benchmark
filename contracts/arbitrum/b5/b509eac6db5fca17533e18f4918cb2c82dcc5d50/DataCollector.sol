// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ICommonFacet.sol";
import "./Oracle.sol";
import "./UniV3Oracle.sol";
import "./OracleRegistry.sol";

import "./DefaultAccessControl.sol";

import "./CommonLibrary.sol";

contract DataCollector is DefaultAccessControl {
    struct Response {
        uint256[] tokenAmounts;
        address[] tokens;
        uint256[] priceToUSDCX96;
        uint256 totalSupply;
        uint256 userBalance;
    }

    struct Request {
        address vault;
        address user;
    }

    uint256 public constant Q96 = 2 ** 96;

    Oracle public immutable usdcOracle;

    constructor(Oracle usdcOracle_, address owner) DefaultAccessControl(owner) {
        usdcOracle = usdcOracle_;
    }

    function convert(
        address token,
        uint256 amount,
        OracleRegistry registry
    ) public view returns (address[] memory tokenList, uint256[] memory amountsList) {
        uint256 numberOfMellowOracles_ = registry.numberOfMellowOracles();
        for (uint256 index = 0; index < numberOfMellowOracles_; index++) {
            (IBaseOracle oracle, IBaseOracle.SecurityParams memory params) = registry.mellowOracles(index);
            if (IMellowBaseOracle(address(oracle)).isTokenSupported(token)) {
                (address[] memory tokens, uint256[] memory amounts) = IMellowBaseOracle(address(oracle)).quote(
                    token,
                    amount,
                    params
                );
                uint256[][] memory subTokenAmounts = new uint256[][](tokens.length);
                address[][] memory subTokens = new address[][](tokens.length);
                for (uint32 i = 0; i < tokens.length; i++) {
                    (subTokens[i], subTokenAmounts[i]) = convert(tokens[i], amounts[i], registry);
                    tokenList = CommonLibrary.merge(tokenList, subTokens[i]);
                }
                amountsList = new uint256[](tokenList.length);

                for (uint32 i = 0; i < tokens.length; i++) {
                    for (uint32 j = 0; j < subTokens[i].length; j++) {
                        uint32 pos = CommonLibrary.binarySearch(tokenList, subTokens[i][j]);

                        require(pos < type(uint32).max, "Invalid state");
                        amountsList[pos] += subTokenAmounts[i][j];
                    }
                }

                return (tokenList, amountsList);
            }
        }

        tokenList = new address[](1);
        amountsList = new uint256[](1);
        tokenList[0] = token;
        amountsList[0] = amount;
    }

    function collect(Request[] memory requests) external view returns (Response[] memory pulseVaultsResponses) {
        pulseVaultsResponses = new Response[](requests.length);

        for (uint32 index = 0; index < requests.length; ++index) {
            ICommonFacet commonFacet = ICommonFacet(requests[index].vault);
            LpToken lpToken = commonFacet.lpToken();
            Oracle oracle = Oracle(address(commonFacet.oracle()));
            OracleRegistry registry = oracle.oracleRegistry();

            (address[] memory tokens, uint256[] memory amounts) = commonFacet.getTokenAmounts();
            uint256[][] memory subTokenAmounts = new uint256[][](tokens.length);
            address[][] memory subTokens = new address[][](tokens.length);

            for (uint32 i = 0; i < tokens.length; i++) {
                (subTokens[i], subTokenAmounts[i]) = convert(tokens[i], amounts[i], registry);
                pulseVaultsResponses[index].tokens = CommonLibrary.merge(pulseVaultsResponses[i].tokens, subTokens[i]);
            }

            pulseVaultsResponses[index].tokenAmounts = new uint256[](pulseVaultsResponses[index].tokens.length);
            pulseVaultsResponses[index].priceToUSDCX96 = new uint256[](pulseVaultsResponses[index].tokens.length);
            pulseVaultsResponses[index].totalSupply = lpToken.totalSupply();
            pulseVaultsResponses[index].userBalance = lpToken.balanceOf(requests[index].user);

            for (uint32 i = 0; i < tokens.length; i++) {
                for (uint32 j = 0; j < subTokens[i].length; j++) {
                    uint32 pos = CommonLibrary.binarySearch(pulseVaultsResponses[index].tokens, subTokens[i][j]);

                    require(pos < type(uint32).max, "Invalid state");
                    pulseVaultsResponses[index].tokenAmounts[pos] += subTokenAmounts[i][j];
                }
            }
            for (uint32 i = 0; i < pulseVaultsResponses[index].tokens.length; i++) {
                address token = pulseVaultsResponses[index].tokens[i];
                uint256[] memory requestingAmounts = new uint256[](1);
                address[] memory requestingTokens = new address[](1);

                requestingTokens[0] = token;
                requestingAmounts[0] = 2 ** 96;

                (address[] memory tmp, , ) = usdcOracle.tokensOrder();
                pulseVaultsResponses[index].priceToUSDCX96[i] = usdcOracle.price(
                    requestingTokens,
                    requestingAmounts,
                    new IBaseOracle.SecurityParams[](1),
                    new IBaseOracle.SecurityParams[](tmp.length)
                );
            }
        }
    }
}

