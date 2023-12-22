// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IProportionalDepositFacet.sol";

import "./FullMath.sol";

contract ProportionalDepositFacet is IProportionalDepositFacet {
    using SafeERC20 for IERC20;

    function proportionalDeposit(
        uint256[] calldata tokenAmounts,
        uint256 minLpAmount
    ) external override returns (uint256 lpAmount, uint256[] memory actualTokenAmounts) {
        IPermissionsFacet(address(this)).requirePermission(msg.sender, address(this), msg.sig);
        ICommonFacet commonFacet = ICommonFacet(address(this));

        (address[] memory tokens, uint256[] memory currentTokenAmounts) = commonFacet.getTokenAmounts();
        require(tokenAmounts.length == currentTokenAmounts.length);
        LpToken lpToken = commonFacet.lpToken();
        uint256 totalSupply = lpToken.totalSupply();

        address vaultAddress = ITokensManagementFacet(address(this)).vault();
        if (totalSupply == 0) {
            for (uint256 i = 0; i < tokenAmounts.length; i++) {
                IERC20(tokens[i]).safeTransferFrom(msg.sender, vaultAddress, tokenAmounts[i]);
                if (lpAmount < tokenAmounts[i]) {
                    lpAmount = tokenAmounts[i];
                }
            }
            lpToken.mint(address(this), lpAmount);
            require(lpAmount >= 10 ** 6 && lpAmount >= minLpAmount, "Limit undeflow");
            return (lpAmount, tokenAmounts);
        }

        lpAmount = type(uint256).max;
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            uint256 amount = FullMath.mulDiv(totalSupply, tokenAmounts[i], currentTokenAmounts[i]);
            if (lpAmount > amount) {
                lpAmount = amount;
            }
        }

        require(lpAmount >= minLpAmount);
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            uint256 amount = FullMath.mulDiv(currentTokenAmounts[i], lpAmount, totalSupply);
            IERC20(tokens[i]).safeTransferFrom(msg.sender, vaultAddress, amount);
            actualTokenAmounts[i] = amount;
        }

        lpToken.mint(msg.sender, lpAmount);
    }
}

