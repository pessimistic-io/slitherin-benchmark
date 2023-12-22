// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { IVoteLockArchi } from "./IVoteLockArchi.sol";

contract TeamTreasury is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    IVoteLockArchi public voteLockArchi;

    event WithdrawTo(address indexed _recipient, uint256 _amountOut);

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /// @notice used to initialize the contract
    function initialize(address _voteLockArchi) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        voteLockArchi = IVoteLockArchi(_voteLockArchi);
    }

    function pendingRewards() public view returns (uint256[] memory) {
        return voteLockArchi.pendingRewards(address(this));
    }

    function claim() external nonReentrant returns (uint256[] memory) {
        return voteLockArchi.claim();
    }

    function withdrawTo(IERC20Upgradeable _token, uint256 _amountOut, address _recipient) external onlyOwner {
        require(address(_token) != address(0), "TeamTreasury: _token cannot be 0x0");
        require(_amountOut > 0, "TeamTreasury: _amountOut cannot be 0");
        require(_recipient != address(0), "TeamTreasury: _recipient cannot be 0x0");

        _token.safeTransfer(_recipient, _amountOut);

        emit WithdrawTo(_recipient, _amountOut);
    }

    function delegateVoting(address _delegatee) external onlyOwner {
        address wrappedToken = voteLockArchi.wrappedToken();
        uint256 stakeAmounts = IERC20Upgradeable(wrappedToken).balanceOf(address(this));

        _approve(wrappedToken, address(voteLockArchi), stakeAmounts);

        voteLockArchi.stake(stakeAmounts, _delegatee);
    }

    function changeDelegator(address _delegatee) external onlyOwner {
        voteLockArchi.delegate(_delegatee);
    }

    function _approve(address _token, address _spender, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}

