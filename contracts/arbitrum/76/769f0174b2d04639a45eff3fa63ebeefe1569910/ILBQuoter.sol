pragma solidity ^0.8.0;

import { IERC20 } from "./ERC20.sol";

interface ILBQuoter {

    struct TraderJoeV2Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        uint256[] amounts;
        uint256[] virtualAmountsWithoutSlippage;
        uint256[] fees;
    }

    function findBestPathFromAmountIn(address[] calldata _route, uint256 _amountIn)
        external
        view
    returns (TraderJoeV2Quote memory quote);
}
