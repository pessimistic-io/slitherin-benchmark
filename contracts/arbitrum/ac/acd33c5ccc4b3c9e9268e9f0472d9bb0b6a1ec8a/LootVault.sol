// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;
import "./IERC20.sol";
import "./Ownable.sol";
import "./RescueFundsLib.sol";

contract LootVault is Ownable {
    using SafeTransferLib for IERC20;

    IERC20 public immutable lootDai__;
    IERC20 public immutable dai__;

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    constructor(address dai_, address lootDai_) {
        dai__ = IERC20(dai_);
        lootDai__ = IERC20(lootDai_);
    }

    function depositDAI(uint256 amount_) external {
        require(
            lootDai__.balanceOf(address(this)) >= amount_,
            "Not enough LootDAI in Vault"
        );
        dai__.safeTransferFrom(msg.sender, address(this), amount_);
        lootDai__.safeTransfer(msg.sender, amount_);
        emit Deposit(msg.sender, amount_);
    }

    function withdrawDAI(uint256 amount_) external {
        require(
            dai__.balanceOf(address(this)) >= amount_,
            "Not enough DAI in Vault"
        );
        lootDai__.safeTransferFrom(msg.sender, address(this), amount_);
        dai__.safeTransfer(msg.sender, amount_);
        emit Withdrawal(msg.sender, amount_);
    }

    function rescueFunds(
        address token_,
        address userAddress_,
        uint256 amount_
    ) external onlyOwner {
        RescueFundsLib.rescueFunds(token_, userAddress_, amount_);
    }
}

