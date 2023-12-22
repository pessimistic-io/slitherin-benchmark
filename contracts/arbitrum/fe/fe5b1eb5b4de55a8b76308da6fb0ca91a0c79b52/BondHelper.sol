// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

import "./IERC20.sol";
import "./Ownable.sol";

import "./IBondDepository.sol";
import "./IWETH.sol";

/// @title Acid Eth Bond helper
/// @notice A helper that helps deposit eth bond

contract BondHelper is Ownable {
    //arb weth
    address public weth;
    address public bondDepository;

    constructor(address _bondDepository, address _weth) {
        bondDepository = _bondDepository;
        weth = _weth;
        IERC20(weth).approve(bondDepository, type(uint256).max);
    }

    /**
     * @notice             deposit quote tokens in exchange for a bond from a specified market
     * @param _id          the ID of the market
     * @param _maxPrice    the maximum price at which to buy
     * @param _user        the recipient of the payout
     * @return payout_     the amount of Acid due
     * @return expiry_     the timestamp at which payout is redeemable
     * @return index_      the user index of the Note (used to redeem or query information)
     */
    function deposit(uint256 _id, uint256 _maxPrice, address _user) external payable returns (uint256 payout_, uint256 expiry_, uint256 index_) {
        IWETH(weth).deposit{value: msg.value}();
        return IBondDepository(bondDepository).deposit(_id, msg.value, _maxPrice, _user);
    }

    function setBondDepositoryAddress(address _bondDepository) external onlyOwner {
        bondDepository = _bondDepository;
        IERC20(weth).approve(bondDepository, type(uint256).max);
    }

    function recoverERC20(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }
}

