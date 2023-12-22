// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./ICollateralModule.sol";
import "./IAccountModule.sol";
import "./IERC721.sol";
import "./Config.sol";
import "./Payments.sol";

/**
 * @title Perform withdrawals and deposits to and from the v2 collateral module
 */
library V2Core {
    function deposit(uint128 accountId, address collateralType, uint256 tokenAmount) internal {
        Payments.approveERC20Core(collateralType, tokenAmount);
        ICollateralModule(Config.load().VOLTZ_V2_CORE_PROXY).deposit(accountId, collateralType, tokenAmount);
    }

    function withdraw(uint128 accountId, address collateralType, uint256 tokenAmount) internal {
        ICollateralModule(Config.load().VOLTZ_V2_CORE_PROXY).withdraw(accountId, collateralType, tokenAmount);
        Payments.pay(collateralType, msg.sender, tokenAmount);
    }

    function createAccount(uint128 requestedId) internal {
        Config.Data memory config = Config.load();
        IAccountModule(config.VOLTZ_V2_CORE_PROXY).createAccount(requestedId);
        IERC721(config.VOLTZ_V2_ACCOUNT_NFT_PROXY).safeTransferFrom(address(this), msg.sender, requestedId);
    }
}

