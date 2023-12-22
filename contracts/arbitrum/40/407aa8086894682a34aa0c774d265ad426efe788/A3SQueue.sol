// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20_IERC20.sol";
import "./Ownable.sol";
import "./IA3SQueue.sol";
import "./IA3SWalletFactoryV3.sol";
import "./A3SQueueHelper.sol";

contract A3SQueue is IA3SQueue, Ownable {
    //keep track of the A3S address's position in mapping
    mapping(address => A3SQueueHelper.Node) public addressNode;
    //Queue head position
    address public headIdx;
    //Queue tail position
    address public tailIdx;
    //Maximum Queue Length temp default set to 200
    uint64 public maxQueueLength;
    //Current Queue Lenght
    uint64 public curQueueLength;
    //ERC20 Token Address
    address public token;
    //Vault Address: performing token transfer for Mint and Steal
    address public vault;
    //Address which receives the jump to tail fee
    address public jumpFeeReceiver;
    //A3SFactoryProxy address
    address public A3SWalletFactory;
    //Deploying timestamp; Unit in Seconds
    uint64 public lastPeriodTimer;
    //The period after which max queue length will be extended; Default is 1 day: 86400; Unit in Seconds; NEED IMPLEMENTATION
    uint64 public queueLenExtPeriod;
    //The Threshold after which max queue length will be extened, Default is 200
    uint64 public queueLenExtCountThld;
    //New IN Queue count for today
    uint64 public periodInQueueCount;
    //Locking Period: in seconds, default is 3 days, might be updated in future
    uint32 public lockingPeriod;
    //Global game start switch: control if game is started or not
    bool public gameStartSwitch;
    //Priority switch: only the OLD (token ID) address could plat
    bool public prioritySwitch;
    //Queue lock - operation requests, manully control when the queue starts to push
    bool public outQueueSwitch;
    //Benchmark player, degined as Old player: ONLY less than the token ID could play
    uint256 public bmPlayer;
    //Parent A3S => Child referring EOA(s)
    mapping(address => mapping(address => bool)) public referringInfoEOA;
    //(Child) Referred EOA Address => (Parent) Referring A3S Addresss
    mapping(address => address) public referredInfo;

    modifier ONLY_GAMESTART() {
        require(gameStartSwitch, "A3S Event not started");
        _;
    }

    constructor(
        address _token,
        address _vault,
        address _jumpFeeReceiver,
        address _A3SWalletFactory,
        uint64 _lastPeriodTimer,
        uint32 _lockingPeriod,
        uint64 _maxQueueLength,
        uint256 _bmPlayer
    ) {
        token = _token;
        vault = _vault;
        jumpFeeReceiver = _jumpFeeReceiver;
        A3SWalletFactory = _A3SWalletFactory;
        lockingPeriod = _lockingPeriod;
        maxQueueLength = _maxQueueLength;
        queueLenExtCountThld = 100;
        queueLenExtPeriod = 86400;
        lastPeriodTimer = _lastPeriodTimer + queueLenExtPeriod;
        bmPlayer = _bmPlayer;
    }

    /**
     * @dev See {IA3SQueue-turnGameStarSwitch, IA3SQueue-turnPrioritySwitch, IA3SQueue-turnOutQueueSwitch}.
     */
    function turnGameStartSwitch() external override onlyOwner {
        if (gameStartSwitch) {
            gameStartSwitch = false;
        } else {
            gameStartSwitch = true;
        }
        emit UpdateSwitches(
            bmPlayer,
            gameStartSwitch,
            prioritySwitch,
            outQueueSwitch
        );
    }

    function turnPrioritySwitch() external override onlyOwner {
        if (prioritySwitch) {
            prioritySwitch = false;
        } else {
            prioritySwitch = true;
        }
        emit UpdateSwitches(
            bmPlayer,
            gameStartSwitch,
            prioritySwitch,
            outQueueSwitch
        );
    }

    function turnOutQueueSwitch() external override onlyOwner {
        if (outQueueSwitch) {
            outQueueSwitch = false;
        } else {
            outQueueSwitch = true;
        }
        emit UpdateSwitches(
            bmPlayer,
            gameStartSwitch,
            prioritySwitch,
            outQueueSwitch
        );
    }

    /**
     * @dev See {IA3SQueue-updateBMPlayer}.
     */
    function updateBMPlayer(uint256 newBMPlayer) external override onlyOwner {
        bmPlayer = newBMPlayer;
        emit UpdateSwitches(
            newBMPlayer,
            gameStartSwitch,
            prioritySwitch,
            outQueueSwitch
        );
    }

    /**
     * @dev See {IA3SQueue-updateLockingDays}.
     */
    function updateLockingPeriod(
        uint32 newlockingPeriod
    ) external override onlyOwner {
        lockingPeriod = newlockingPeriod;
        emit UpdateLockingPeriod(newlockingPeriod, token);
    }

    /**
     * @dev See {IA3SQueue-updateMaxQueueLength}.
     */
    function updateQueueLenExtPeriod(uint64 maximumQLExtP) external onlyOwner {
        queueLenExtPeriod = maximumQLExtP;
    }

    function updateQueueLenExtCountThld(
        uint64 maximumQLExtThld
    ) external onlyOwner {
        queueLenExtCountThld = maximumQLExtThld;
    }

    function updateMaxQueueLength(
        uint64 maximumQL
    ) external override onlyOwner {
        maxQueueLength = maximumQL;
    }

    function updatelastPeriodTimer(
        uint64 new_lastPeriodTimer
    ) external onlyOwner {
        require(
            new_lastPeriodTimer > uint64(block.timestamp),
            "A3S: new lastPeriodTimer must be higher than current time"
        );
        lastPeriodTimer = new_lastPeriodTimer;
    }

    function updateVault(address new_vault) external override onlyOwner {
        require(new_vault != address(0), "A3S: Invalid address");
        vault = new_vault;
    }

    function updateJumpFeeReceiver(
        address new_jumpFeeReceiver
    ) external override onlyOwner {
        require(new_jumpFeeReceiver != address(0), "A3S: Invalid address");
        jumpFeeReceiver = new_jumpFeeReceiver;
    }

    function updateA3SToken(address new_token) external override onlyOwner {
        require(new_token != address(0), "A3S: Invalid address");
        token = new_token;
    }

    /**
     * @dev See {IA3SQueue-pushIn}.
     */
    function pushIn(address addr) external override ONLY_GAMESTART {
        //if priority in queue switch OFF, normal pushin
        //otherwise, ONLY tokenID <= bmPlayer could play
        if (!prioritySwitch) {
            _pushIn(addr);
        } else {
            uint256 tokenId = IA3SWalletFactoryV3(A3SWalletFactory).walletIdOf(
                addr
            );
            if (tokenId <= bmPlayer && tokenId != 0) {
                _pushIn(addr);
            }
        }
    }

    /**
     * @dev See {IA3SQueue-jumpToSteal}.
     */
    function jumpToSteal(
        address jumpingAddr,
        address stolenAddr
    ) external override ONLY_GAMESTART {
        //If jumpingAddr is already tailIdx, no need to Jump to Tail
        if (jumpingAddr != tailIdx) {
            _jumpToTail(jumpingAddr);
        }
        //Make sure the jumping address is at queue tail
        if (jumpingAddr == tailIdx && stolenAddr != address(0)) {
            A3SQueueHelper._steal(
                stolenAddr,
                tailIdx,
                lockingPeriod,
                token,
                vault,
                addressNode
            );
        }
    }

    /**
     * @dev See {IA3SQueue-jumpToTail}.
     */
    function jumpToTail(address jumpingAddr) external override ONLY_GAMESTART {
        _jumpToTail(jumpingAddr);
    }

    /**
     * @dev See {IA3SQueue-mint}.
     */
    function mint(address addr) external override ONLY_GAMESTART {
        A3SQueueHelper._mint(
            addr,
            token,
            A3SWalletFactory,
            lockingPeriod,
            addressNode,
            referredInfo
        );
    }

    /**
     * @dev See {IA3SQueue-batchMint}.
     */
    function batchMint(
        address[] memory addrs
    ) external override ONLY_GAMESTART {
        for (uint16 i = 0; i < addrs.length; i++) {
            A3SQueueHelper._mint(
                addrs[i],
                token,
                A3SWalletFactory,
                lockingPeriod,
                addressNode,
                referredInfo
            );
        }
    }

    function _pushIn(address _addr) internal {
        require(_addr != address(0));
        require(
            addressNode[_addr].addr == address(0),
            "A3S: address played and invalid to queue"
        );
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletIdOf(_addr) != 0,
            "A3S: address is not a valid A3S address"
        );
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletOwnerOf(_addr) ==
                msg.sender,
            "A3S: ONLY wallet owner could push in"
        );
        A3SQueueHelper.Node memory new_node = A3SQueueHelper.Node({
            addr: _addr,
            balance: 0,
            inQueueTime: uint64(block.timestamp),
            prev: address(0),
            next: address(0),
            outQueueTime: 0,
            stat: A3SQueueHelper.queueStatus.INQUEUE
        });
        if (headIdx == address(0)) {
            new_node.prev = _addr;
            headIdx = _addr;
            tailIdx = _addr;
        } else {
            new_node.next = tailIdx;
            //Update the next node
            addressNode[tailIdx].prev = _addr;
            tailIdx = _addr;
        }
        addressNode[_addr] = new_node;
        curQueueLength += 1;
        //Check the timestamp and update：lastPeriodTimer/preDayInQueueCount/periodInQueueCount
        //Within Today/Period
        if (uint64(block.timestamp) <= lastPeriodTimer) {
            periodInQueueCount += 1;
        }
        //Within Next Day/Period
        else if (
            uint64(block.timestamp) > lastPeriodTimer &&
            uint64((block.timestamp)) - lastPeriodTimer <= queueLenExtPeriod
        ) {
            lastPeriodTimer += queueLenExtPeriod;
            //previous day in Queue Count will set to periodInQueueCount;
            //periodInQueueCount = 1;
            //Update maxQueueLenght based on Previous Day in queue count
            if (periodInQueueCount >= queueLenExtCountThld) {
                uint64 _extended = A3SQueueHelper._getExtendLength(
                    periodInQueueCount
                );
                maxQueueLength += _extended;
            }
            periodInQueueCount = 1;
        }
        //WIthin More than 1 day
        //Pre Day in queue is 0, no need to update max length
        //Get today's inqueue from 1
        else {
            uint64 extendedPeriodCount = uint64(
                (uint64((block.timestamp)) - lastPeriodTimer) /
                    queueLenExtPeriod
            ) + 1;
            lastPeriodTimer += extendedPeriodCount * queueLenExtPeriod;
            periodInQueueCount = 1;
        }
        //Check if Maximum Length reached and Start Push
        address pushedOutAddr;
        if (curQueueLength > maxQueueLength && !outQueueSwitch) {
            pushedOutAddr = _pushOut();
        }
        emit PushIn(
            _addr,
            addressNode[_addr].prev,
            addressNode[_addr].next,
            addressNode[_addr].inQueueTime,
            headIdx,
            tailIdx,
            curQueueLength,
            pushedOutAddr,
            addressNode[pushedOutAddr].balance
        );
    }

    function _pushOut() internal returns (address) {
        //Pushed out the Head A3SQueueHelper.Node
        address _cur_addr = headIdx;
        addressNode[_cur_addr].stat = A3SQueueHelper.queueStatus.PENDING;
        addressNode[_cur_addr].outQueueTime = uint64(block.timestamp);
        address payable A3SWalletFactory_payable = payable(A3SWalletFactory);
        addressNode[_cur_addr].balance = uint256(
            A3SQueueHelper._getTokenAmount(
                _cur_addr,
                A3SWalletFactory_payable,
                addressNode
            )
        );
        //Update the headIdx
        headIdx = addressNode[headIdx].prev;
        //Update current queue length
        curQueueLength -= 1;
        return _cur_addr;
    }

    function _jumpToTail(address _addr) internal {
        require(_addr != address(0));
        require(
            addressNode[_addr].stat == A3SQueueHelper.queueStatus.INQUEUE,
            "A3S: Operation failed, the address is no longer in the queue"
        );
        require(_addr != tailIdx, "A3S: already in queue tail!");
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletOwnerOf(_addr) ==
                msg.sender,
            "A3S: ONLY wallet owner could proceed"
        );
        uint256 _payment = A3SQueueHelper._getJumpToTailFee(
            addressNode[_addr].inQueueTime
        );
        require(
            IERC20(token).transferFrom(msg.sender, jumpFeeReceiver, _payment),
            "A3S: Payment failed!"
        );
        //Get old Prev and next Pointer for Event
        address _old_prev = addressNode[_addr].prev;
        address _old_next = addressNode[_addr].next;
        //If current node is head
        if (_addr == headIdx) {
            //Update the new head nodes
            addressNode[tailIdx].prev = _addr;
            addressNode[_addr].next = tailIdx;
            addressNode[addressNode[_addr].prev].next = address(0);
            headIdx = addressNode[_addr].prev;
        } else {
            //Update the neighbor nodes
            addressNode[addressNode[_addr].next].prev = addressNode[_addr].prev;
            addressNode[addressNode[_addr].prev].next = addressNode[_addr].next;
        }
        //Update the next and prev node
        addressNode[_addr].next = tailIdx;
        addressNode[_addr].prev = address(0);
        //Update previous tail node
        addressNode[tailIdx].prev = _addr;
        //Update the current tail index
        tailIdx = _addr;

        emit JumpToTail(
            _addr,
            headIdx,
            tailIdx,
            curQueueLength,
            _payment,
            token,
            _old_prev,
            _old_next,
            addressNode[_addr].next
        );
    }

    /**
     * @dev Check if the EOA address is able to be referred
     *
     * @param referringEOA the EOA which is checked by the function
     * Requirements:
     * 1. It's key from mapping should be empty: it has not been referred before
     * 2. If the EOA has minted A3S address and NONE of the A3S has played the queue game before
     *
     */

    function isAbleToRefer(address referringEOA) public view returns (bool) {
        require(referringEOA != address(0), "A3S: referring EOA is 0 address");
        if (referredInfo[referringEOA] != address(0)) {
            return false;
        }
        A3SWalletFactoryV3 a3sContract = A3SWalletFactoryV3(
            payable(A3SWalletFactory)
        );
        address[] memory ownA3SList = a3sContract.walletListOwnerOf(
            referringEOA
        );
        if (ownA3SList.length > 0) {
            for (uint256 i = 0; i < ownA3SList.length; i++) {
                if (addressNode[ownA3SList[i]].addr != address(0)) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @dev Refer Relationship added on chain:
     *
     * @param parentA3S the A3S which refers
     * @param referringEOA the EOA which is referred by parentA3S
     *
     * Requirements:
     * 1. It's key from mapping should be empty: it has not been referred before
     * 2. If the EOA has minted A3S address and NONE of the A3S has played the queue game before
     *
     */
    function initReferEOA(address parentA3S, address referringEOA) external {
        address owner_of_parentA3S = IA3SWalletFactoryV3(A3SWalletFactory)
            .walletOwnerOf(parentA3S);
        require(
            parentA3S != address(0) && referringEOA != address(0),
            "A3S: parentA3S and referred EOA should not be 0 address"
        );
        require(
            referringEOA == msg.sender,
            "A3S: calling user must be referring EOA"
        );
        require(
            owner_of_parentA3S != address(0),
            "A3S: parent A3S is Not a valid A3S address"
        );
        require(
            owner_of_parentA3S != referringEOA,
            "A3S: The operation failed, you cannot be referred by your own A3S address"
        );
        address parentA3Sreferral = referredInfo[owner_of_parentA3S];
        if (parentA3Sreferral != address(0)) {
            require(
                IA3SWalletFactoryV3(A3SWalletFactory).walletOwnerOf(
                    parentA3Sreferral
                ) != referringEOA,
                "A3S: The operation failed, you cannot be referred by your referee's A3S address"
            );
        }
        require(
            isAbleToRefer(referringEOA),
            "A3S: the EOA is not qualified to be referred"
        );

        A3SQueueHelper._initReferEOA(
            parentA3S,
            referringEOA,
            referringInfoEOA,
            referredInfo,
            A3SWalletFactory
        );
    }
}

