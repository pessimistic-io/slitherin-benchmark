// SPDX-License-Identifier: GPL2
pragma solidity 0.8.10;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";

import "./IMintable.sol";

contract Migration is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant MUX_MIGRATION_FACTOR = 10;

    uint256 public totalMigrated;
    IERC20Upgradeable public mcbToken;
    IMintable public muxToken;

    event Migrate(address indexed sender, uint256 mcbAmount, uint256 muxAmount);

    function initialize(address mcbToken_, address muxToken_)
        external
        initializer
    {
        __Ownable_init();
        mcbToken = IERC20Upgradeable(mcbToken_);
        muxToken = IMintable(muxToken_);
    }

    function migrate(uint256 amount) external nonReentrant {
        require(amount > 0, "amount is zero");
        mcbToken.transferFrom(msg.sender, address(this), amount);
        totalMigrated += amount;
        uint256 muxAmount = amount * MUX_MIGRATION_FACTOR;
        muxToken.mint(msg.sender, muxAmount);

        emit Migrate(msg.sender, amount, muxAmount);
    }

    function rescue() external onlyOwner nonReentrant {
        uint256 misTransferred = mcbToken.balanceOf(address(this)) -
            totalMigrated;
        if (misTransferred > 0) {
            mcbToken.safeTransfer(msg.sender, misTransferred);
        }
    }
}

