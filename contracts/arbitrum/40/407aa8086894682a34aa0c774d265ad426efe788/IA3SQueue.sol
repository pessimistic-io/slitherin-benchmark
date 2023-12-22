// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./A3SQueueHelper.sol";

interface IA3SQueue {
    /**
     * @dev Operation purpose: Manually turn on/off to start/stop the game: true: able to play
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function turnGameStartSwitch() external;

    /**
     * @dev Operation purpose: Manually turn on/off the queue to ONLY allow old User(TokenID) to play: ture: ONLY smaller TokenID could play
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function turnPrioritySwitch() external;

    /**
     * @dev Operation purpose: Manually turn on/off the queue to allow PushOut: true: ONLY pushin NO pushouts
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function turnOutQueueSwitch() external;

    /**
     * @dev Operation purpose: update the benchmark player ID, default is 200 - means if turnPrioritySwitch is TRUE, only tokenID less than 200 could be in queue
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function updateBMPlayer(uint256 newBMPlayer) external;

    /**
     * @dev Operation purpose: update the locking days, default is 3 days
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function updateLockingPeriod(uint32 newlockingDays) external;

    /**
     * @dev Operation purpose: update the Maximum Queue Length, default is 300
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function updateMaxQueueLength(uint64 maximumQL) external;

    /**
     * @dev Operation purpose: update the vault address
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function updateVault(address new_vault) external;

    /**
     * @dev Operation purpose: update the vault address
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function updateJumpFeeReceiver(address new_jumpFeeReceiver) external;

    /**
     * @dev Push Node into queue, initiate the Node status
     *      Calculate the today's in queue count 'todayInQueueCount', previous day's in queue count 'preDayInQueueCount'
     *      Extend the Maxium queue Length 'maxQueueLength' based on previous day's in queue count
     *      If the current queue length 'curQueueLength' exceed the maximum queue length - Push Out the head node
     *
     * Requirements:
     *
     * - `gameStartSwitch` must be ON (true)
     * - `_addr` must not be O address.
     * - `_addr` must be 1st time play: addressNode[_addr].addr == address(0)
     * - `_addr` must be a valid A3S address: Address tokenId not to be 0.
     *
     * Emits a {Push In} event.
     */
    function pushIn(address addr) external;

    /**
     * @dev Put 'jumpingAddr' to queue tail, Steal the 'stolenAddr' $A
     *
     * Requirements:
     *
     * - `jumpingAddr` & 'stolenAddr' must not be O address.
     *
     * Separately Emits a {JumpToTail} and {Steal} event.
     */
    function jumpToSteal(address jumpingAddr, address stolenAddr) external;

    /**
     * @dev Put 'jumpingAddr' to queue tail
     *
     * Requirements:
     *
     * - `jumpingAddr` must not be O address.
     *
     * Emits a {JumpToTail} event.
     */
    function jumpToTail(address jumpingAddr) external;

    /**
     * @dev Mint the $A for the address
     *      calling IERC20 transferFrom(valut, _addr, tokenAmount)
     *
     * Requirements:
     *
     * - `gameStartSwitch` must be ON (true)
     * - `_addr` must not be O address.
     * - '_addr''s walletOwnerOf must be msg.sender - ONLY owner could mint $A
     *
     * Emits a {Mint} event.
     */
    function mint(address addr) external;

    /**
     * @dev Batch Mint the $A for all the address of current owner
     * Requirements:
     *
     * - `gameStartSwitch` must be ON (true)
     */
    function batchMint(address[] memory addr) external;

    /**
     * @dev Update A3S Token Address
     * Requirements:
     *
     * - `new_token` must not be address(0)
     */
    function updateA3SToken(address new_token) external;

    /**
     * @dev Events definition
     */
    event PushIn(
        address addr,
        address prev,
        address next,
        uint64 inQueueTime,
        address headIdx,
        address tailIdx,
        uint64 curQueueLength,
        address pushedOutAddress,
        uint256 balance
    );

    event JumpToTail(
        address jumpingAddr,
        address headIdx,
        address tailIdx,
        uint64 curQueueLength,
        uint256 payment,
        address token,
        address oldPrev,
        address oldNext,
        address curNext
    );

    event Steal(address stealAddr, address stolenAddr, uint256 amount);
    event Mint(address addr, uint256 mintAmount);
    event UpdateLockingPeriod(uint32 newlockingPeriod, address tokenAddress);
    event UpdateSwitches(
        uint256 tokenId,
        bool gameStartSwitch,
        bool prioritySwitch,
        bool outQueueSwitch
    );
    event ReferralMint(address referringAddr, address referredAddr, uint256 referringAmount, uint256 referredAmount);
    event InitReferEOA(address parentA3S, address referringEOA);
}

