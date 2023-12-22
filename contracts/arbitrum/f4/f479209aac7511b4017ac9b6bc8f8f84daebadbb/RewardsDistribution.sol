//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";

interface ISSOV {
    function deposit(uint256 strikeIndex, uint256 amount)
        external
        returns (bool);

    function withdraw(uint256 epoch, uint256 strikeIndex)
        external
        returns (uint256[2] memory);

    function currentEpoch() external view returns (uint256);
}

contract RewardsDistribution is Ownable {
    using SafeERC20 for IERC20;

    /// @dev ETH SSOV address
    address public immutable ethSsov;

    /// @dev DPX SSOV contract
    ISSOV public immutable dpxSsov;

    /// @dev DPX token contract
    IERC20 public immutable dpx;

    /// @dev rDPX token contract
    IERC20 public immutable rdpx;

    /// @dev epoch => amount
    mapping(uint256 => uint256) public dpxReceived;

    /// @dev epoch => amount
    mapping(uint256 => uint256) public rdpxReceived;

    /// @param _ethSsov ETH SSOV address
    /// @param _dpxSsov DPX SSOV address
    /// @param _dpx DPX token address
    /// @param _rdpx rDPX token address
    constructor(
        address _ethSsov,
        address _dpxSsov,
        address _dpx,
        address _rdpx
    ) {
        ethSsov = _ethSsov;
        dpxSsov = ISSOV(_dpxSsov);
        dpx = IERC20(_dpx);
        rdpx = IERC20(_rdpx);
    }

    /// @notice Transfer rewards and deposit to DPX SSOV
    /// @param strikeIndex Strike index in the DPX ssov to deposit in
    /// @param amount Amount of DPX rewards
    function deposit(uint256 strikeIndex, uint256 amount) external onlyOwner {
        dpx.safeTransferFrom(msg.sender, address(this), amount);
        dpxSsov.deposit(strikeIndex, amount);
    }

    /// @notice Withdraw rewards from DPX SSOV
    /// @param dpxEpoch Epoch to withdraw from in DPX SSOV
    /// @param ethEpoch Epoch to store rewards for ETH SSOV
    /// @param strikeIndex Strike Index to withdraw from
    function withdraw(
        uint256 dpxEpoch,
        uint256 ethEpoch,
        uint256 strikeIndex
    ) external onlyOwner {
        uint256[2] memory returnValues = dpxSsov.withdraw(
            dpxEpoch,
            strikeIndex
        );

        dpxReceived[ethEpoch] = returnValues[0];
        rdpxReceived[ethEpoch] = returnValues[1];
    }

    /// @notice Stop rewards
    function stop() external onlyOwner {
        dpx.safeTransfer(msg.sender, dpx.balanceOf(address(this)));
        rdpx.safeTransfer(msg.sender, rdpx.balanceOf(address(this)));

        uint256 epoch = ISSOV(ethSsov).currentEpoch();

        dpxReceived[epoch] = 0;
        rdpxReceived[epoch] = 0;
    }

    /// @notice Let ETH SSOV pull rewards DPX (and rDPX) rewards
    /// @param epoch Epoch
    function pull(
        uint256 epoch,
        uint256 userDeposit,
        uint256 totalDeposit,
        address user
    ) external returns (uint256 dpxRewards, uint256 rdpxRewards) {
        require(
            msg.sender == ethSsov,
            'RewardsDistribution: Caller must be ETH SSOV'
        );
        dpxRewards = (dpxReceived[epoch] * userDeposit) / totalDeposit;
        rdpxRewards = (rdpxReceived[epoch] * userDeposit) / totalDeposit;
        dpx.safeTransfer(user, dpxRewards);
        rdpx.safeTransfer(user, rdpxRewards);
    }
}

