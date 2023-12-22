// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IProportionalWithdrawFacet.sol";
import "./FullMath.sol";

contract ProportionalWithdrawFacet is IProportionalWithdrawFacet {
    using SafeERC20 for IERC20;

    function proportionalWithdrawal(
        uint256 lpAmount,
        uint256[] memory minTokenAmounts
    ) external override returns (uint256[] memory tokenAmounts) {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        ICommonFacet commonFacet = ICommonFacet(address(this));
        LpToken lpToken = commonFacet.lpToken();
        uint256 totalSupply = lpToken.totalSupply();
        lpToken.burn(msg.sender, lpAmount);
        (address[] memory tokens, uint256[] memory currentTokenAmounts) = commonFacet.getTokenAmounts();

        require(minTokenAmounts.length == tokens.length);
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenAmount = FullMath.mulDiv(currentTokenAmounts[i], lpAmount, totalSupply);
            require(tokenAmount >= minTokenAmounts[i]);
            IERC20(tokens[i]).safeTransfer(msg.sender, tokenAmount);
            tokenAmounts[i] = tokenAmount;
        }
    }
}

