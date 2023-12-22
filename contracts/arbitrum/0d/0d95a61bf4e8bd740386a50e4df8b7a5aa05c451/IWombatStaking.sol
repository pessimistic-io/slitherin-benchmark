// SPDX-License-Identifier: MIT

import {IERC20} from "./ERC20.sol";

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IWombatStaking {
    struct Pool {
        uint256 pid; // pid on master wombat
        address depositToken; // token to be deposited on wombat
        address lpAddress; // token received after deposit on wombat
        address receiptToken; // token to receive after
        address rewarder;
        address helper;
        address depositTarget;
        bool isActive;
    }

    function convertWOM(uint256 amount) external returns (uint256);

    function masterWombat() external view returns (address);

    function deposit(
        address _lpToken,
        uint256 _amount,
        uint256 _minAmount,
        address _for,
        address _from
    ) external;

    function depositLP(
        address _lpToken,
        uint256 _lpAmount,
        address _for
    ) external;

    function withdraw(
        address _lpToken,
        uint256 _amount,
        uint256 _minAmount,
        address _sender
    ) external;

    function getPoolLp(address _lpToken) external view returns (address);

    function pools(address _lpToken) external view returns (Pool memory);

    function harvest(address _lpToken) external;

    function burnReceiptToken(address _lpToken, uint256 _amount) external;

    function vote(
        address[] calldata _lpVote,
        int256[] calldata _deltas,
        address[] calldata _rewarders,
        address caller
    )
        external
        returns (
            address[][] memory rewardTokens,
            uint256[][] memory feeAmounts
        );

    function voter() external view returns (address);

    function pendingBribeCallerFee(
        address[] calldata pendingPools
    )
        external
        view
        returns (
            IERC20[][] memory rewardTokens,
            uint256[][] memory callerFeeAmount
        );
}

