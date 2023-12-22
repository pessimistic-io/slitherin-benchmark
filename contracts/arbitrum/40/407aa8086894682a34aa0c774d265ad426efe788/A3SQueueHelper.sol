// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./A3SWalletFactoryV3.sol";
import "./IA3SToken.sol";
import "./IA3SWalletFactoryV3.sol";
import "./ABDKMathQuad.sol";
import "./SafeMath.sol";

library A3SQueueHelper {
    using ABDKMathQuad for uint256;
    using ABDKMathQuad for bytes16;
    using SafeMath for uint256;

    /**
     * @dev Node structure
     *
     * - `prev` previous pointer, point to right.
     * - `next` previous pointer, point to left.
     * - `balance` calculated $A balance: only assigned value when node is pushed out of queue
     * - `inQueueTime` timestamp when pushed into queue.
     * - `outQueueTime` timestamp when pushed out of queue.
     * - `queueStatus` Node status.
     *
     */
    struct Node {
        address addr;
        address prev;
        address next;
        uint256 balance;
        uint64 inQueueTime;
        uint64 outQueueTime;
        queueStatus stat;
    }

    enum queueStatus {
        INQUEUE,
        PENDING,
        CLAIMED,
        STOLEN
    }

    function _mint(
        address _addr,
        address _token,
        address _A3SWalletFactory,
        uint32 _lockingPeriod,
        mapping(address => Node) storage _addressNode,
        mapping(address => address) storage _referredInfo
    ) internal {
        //Require minted addrss belongs to msg.sender
        require(
            IA3SWalletFactoryV3(_A3SWalletFactory).walletOwnerOf(_addr) ==
                msg.sender,
            "A3S: ONLY owner can mint"
        );
        require(
            _addressNode[_addr].outQueueTime > 0,
            "A3S: NOT valid to calim - not pushed"
        );
        require(
            _addressNode[_addr].stat == A3SQueueHelper.queueStatus.PENDING,
            "A3S: ONLY pending status could be claimed"
        );
        require(
            uint64(block.timestamp) - _addressNode[_addr].outQueueTime <
                _lockingPeriod * 1 seconds,
            "A3S: $AA has been expired to be claimed, claim failed"
        );
        uint256 _balance = _addressNode[_addr].balance;
        _addressNode[_addr].stat = queueStatus.CLAIMED;
        _addressNode[_addr].balance = 0;

        IA3SToken(_token).mint(_addr, _balance);

        //Check if Referred, if so deduct the reward and calculate the givenOutReward
        if (
            _referredInfo[
                IA3SWalletFactoryV3(_A3SWalletFactory).walletOwnerOf(_addr)
            ] != address(0)
        ) {
            address _referringAddr = _referredInfo[
                IA3SWalletFactoryV3(_A3SWalletFactory).walletOwnerOf(_addr)
            ];
            bytes16 x15 = uint256(15).fromUInt().div(uint256(100).fromUInt()); //calculate 15% = 0.15
            bytes16 x5 = uint256(5).fromUInt().div(uint256(100).fromUInt()); //calculate 5% = 0.05
            uint256 _RewardForReferring = (_balance.fromUInt().mul(x15))
                .toUInt();
            uint256 _RewardForReferred = (_balance.fromUInt().mul(x5)).toUInt();
            IA3SToken(_token).mint(_referringAddr, _RewardForReferring);
            IA3SToken(_token).mint(_addr, _RewardForReferred);
            emit ReferralMint(
                _referringAddr,
                _addr,
                _RewardForReferring,
                _RewardForReferred
            );
        }

        emit Mint(_addr, _balance);
    }

    function _steal(
        address _addr,
        address _tailIdx,
        uint32 _lockingPeriod,
        address _token,
        address _vault,
        mapping(address => Node) storage _addressNode
    ) internal {
        require(
            _addressNode[_addr].stat == A3SQueueHelper.queueStatus.PENDING,
            "A3S: $AA has been picked up"
        );
        require(
            uint64(block.timestamp) - _addressNode[_addr].outQueueTime >=
                _lockingPeriod * 1 seconds,
            "A3S: NOT valid to steal - not reaching locking period"
        );
        //Update balance for the stolen address
        uint256 _balance = _addressNode[_addr].balance;
        _addressNode[_addr].balance = 0;
        _addressNode[_addr].stat = A3SQueueHelper.queueStatus.STOLEN;
        //50% of balance will be minted directly to the stealing(tail) address
        //The rest 50% of balance will be minted to the vault address
        //A3SToken token = A3SToken(_token);
        IA3SToken(_token).mint(_tailIdx, _balance.div(2));
        IA3SToken(_token).mint(_vault, _balance.div(2));

        emit Steal(_tailIdx, _addr, _balance.div(2));
    }

    function _getJumpToTailFee(
        uint256 _inQueueTimestamp
    ) internal view returns (uint256) {
        uint256 _T = 1;

        uint16[16] memory _fibonacci = [
            1,
            2,
            3,
            5,
            8,
            13,
            21,
            34,
            55,
            89,
            144,
            233,
            377,
            610,
            987,
            1597
        ];

        for (uint256 i = 0; i <= 15; i++) {
            if (
                ((block.timestamp - _inQueueTimestamp) / 86400) >=
                _fibonacci[i] &&
                ((block.timestamp - _inQueueTimestamp) / 86400) <
                _fibonacci[i + 1]
            ) {
                _T = _fibonacci[i];
            }
        }

        return _T * (10 ** 18);
    }

    function _getTokenAmount(
        address _addr,
        address payable _A3SWalletFactory,
        mapping(address => Node) storage _address_node
    ) internal view returns (uint256 amount) {
        uint16[16] memory _fibonacci = [
            1,
            2,
            3,
            5,
            8,
            13,
            21,
            34,
            55,
            89,
            144,
            233,
            377,
            610,
            987,
            1597
        ];
        A3SWalletFactoryV3 a3sContract = A3SWalletFactoryV3(_A3SWalletFactory);
        //Get DiffID; DiffID = ID(all) - ID(user) + 1.1
        bytes16 _diffID = a3sContract
            .tokenIdCounter()
            .fromUInt()
            .sub(
                uint256(
                    IA3SWalletFactoryV3(_A3SWalletFactory).walletIdOf(_addr)
                ).fromUInt()
            )
            .add(uint256(11).fromUInt().div(uint256(10).fromUInt()));
        //N = 1.1 + 0.1 * ()
        bytes16 _n = A3SQueueHelper._getN(
            uint256(IA3SWalletFactoryV3(_A3SWalletFactory).walletIdOf(_addr))
        );
        //T: from _fibonacci array
        uint256 _T = 1;
        for (uint256 i = 0; i <= 15; i++) {
            if (
                ((block.timestamp - _address_node[_addr].inQueueTime) /
                    86400) >=
                _fibonacci[i] &&
                ((block.timestamp - _address_node[_addr].inQueueTime) / 86400) <
                _fibonacci[i + 1]
            ) {
                _T = _fibonacci[i];
            }
        }
        bytes16 _amount = ABDKMathQuad
            .log_2(_diffID)
            .div(ABDKMathQuad.log_2(_n))
            .mul(uint256(10 ** 18).fromUInt())
            .mul(_T.fromUInt())
            .mul(uint256(415).fromUInt().div(uint256(100).fromUInt())); //r=4.15
        amount = _amount.toUInt();
    }

    function _getN(uint256 _diffID) internal pure returns (bytes16 n) {
        bytes16 m = uint256(11).fromUInt().div(uint256(10).fromUInt());
        bytes16 q = uint256(1).fromUInt().div(uint256(10).fromUInt());
        bytes16 k = uint256(_diffID / uint256(100)).fromUInt();
        n = m.add(q.mul(k));
    }

    function _getExtendLength(
        uint64 _prevDayIncreCount
    ) internal pure returns (uint64 extendLength) {
        uint16[21] memory _index = [
            9,
            33,
            69,
            114, 
            167,
            225,
            288,
            356,
            426,
            500,
            576,
            655,
            735,
            817,
            900,
            985,
            1070,
            1157,
            1245,
            1333,
            1423
        ];

        uint64 n = _prevDayIncreCount / 100;
        if (n >= 22) {
            extendLength = 1423;
        } else {
            extendLength = uint64(_index[n - 1]);
        }
    }

    function _initReferEOA(
        address _parentA3S,
        address _referringEOA,
        mapping(address => mapping(address => bool)) storage _referringInfoEOA,
        mapping(address => address) storage _referredInfo,
        address _A3SWalletFactory
    ) internal {
        require(
            _parentA3S != address(0) && _referringEOA != address(0),
            "A3S: Invalid Address input, ZERO address"
        );
        //check if the referring EOA was referred before
        require(
            _referredInfo[_referringEOA] == address(0),
            "A3S: the refer adress was referred before"
        );
        //check if the parent A3S's EOA address was invited, and if true, its referral cannot be referring EOA
        address parentA3Sreferral = _referredInfo[
            IA3SWalletFactoryV3(_A3SWalletFactory).walletOwnerOf(_parentA3S)
        ];
        if (parentA3Sreferral != address(0)) {
            require(
                IA3SWalletFactoryV3(_A3SWalletFactory).walletOwnerOf(
                    parentA3Sreferral
                ) != _referringEOA,
                "A3S: referring EOA has previously referred the A3S address"
            );
        }

        _referredInfo[_referringEOA] = _parentA3S;

        _referringInfoEOA[_parentA3S][_referringEOA] = true;

        emit InitReferEOA(_parentA3S, _referringEOA);
    }

    event Steal(address stealAddr, address stolenAddr, uint256 amount);
    event Mint(address addr, uint256 mintAmount);
    event ReferralMint(
        address referringAddr,
        address referredAddr,
        uint256 referringAmount,
        uint256 referredAmount
    );
    event InitReferEOA(address parentA3S, address referringEOA);
}

