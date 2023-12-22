// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract Owned {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert();
        }
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }

    function terminate() public onlyOwner {
        selfdestruct(payable(owner));
    }
}

contract YlideMailerV7 is Owned {

    uint256 public version = 7;

    uint256 constant empty0 = 0x00ff000000ffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant empty1 = 0x00ffffffff000000ffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant empty2 = 0x00ffffffffffffff000000ffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant empty3 = 0x00ffffffffffffffffffff000000ffffffffffffffffffffffffffffffffffff;
    uint256 constant empty4 = 0x00ffffffffffffffffffffffffff000000ffffffffffffffffffffffffffffff;
    uint256 constant empty5 = 0x00ffffffffffffffffffffffffffffffff000000ffffffffffffffffffffffff;
    uint256 constant empty6 = 0x00ffffffffffffffffffffffffffffffffffffff000000ffffffffffffffffff;
    uint256 constant empty7 = 0x00ffffffffffffffffffffffffffffffffffffffffffff000000ffffffffffff;
    uint256 constant empty8 = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffff000000ffffff;
    uint256 constant empty9 = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000;

    uint256 constant index1 = 0x0100000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index2 = 0x0200000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index3 = 0x0300000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index4 = 0x0400000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index5 = 0x0500000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index6 = 0x0600000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index7 = 0x0700000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index8 = 0x0800000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index9 = 0x0900000000000000000000000000000000000000000000000000000000000000;

    uint256 public contentPartFee = 0;
    uint256 public recipientFee = 0;
    address payable public beneficiary;

    mapping (uint256 => uint256) public recipientToPushIndex;
    mapping (address => uint256) public senderToBroadcastIndex;

    mapping (uint256 => uint256) public recipientMessagesCount;
    mapping (address => uint256) public broadcastMessagesCount;

    event MailPush(uint256 indexed recipient, address indexed sender, uint256 msgId, uint256 mailList, bytes key);
    event MailContent(uint256 indexed msgId, address indexed sender, uint16 parts, uint16 partIdx, bytes content);
    event MailBroadcast(address indexed sender, uint256 msgId, uint256 mailList);

    constructor() {
        beneficiary = payable(msg.sender);
    }

    function shiftLeft(uint256 a, uint256 n) public pure returns (uint256) {
        return uint256(a * 2 ** n);
    }
    
    function shiftRight(uint256 a, uint256 n) public pure returns (uint256) {
        return uint256(a / 2 ** n);
    }

    function nextIndex(uint256 orig, uint256 val) public pure returns (uint256 result) {
        val = val & 0xffffff; // 3 bytes
        uint8 currIdx = uint8(shiftRight(orig, 248));
        if (currIdx == 9) {
            return (orig & empty0) | shiftLeft(val, 216);
        } else
        if (currIdx == 0) {
            return (orig & empty1) | index1 | shiftLeft(val, 192);
        } else
        if (currIdx == 1) {
            return (orig & empty2) | index2 | shiftLeft(val, 168);
        } else
        if (currIdx == 2) {
            return (orig & empty3) | index3 | shiftLeft(val, 144);
        } else
        if (currIdx == 3) {
            return (orig & empty4) | index4 | shiftLeft(val, 120);
        } else
        if (currIdx == 4) {
            return (orig & empty5) | index5 | shiftLeft(val, 96);
        } else
        if (currIdx == 5) {
            return (orig & empty6) | index6 | shiftLeft(val, 72);
        } else
        if (currIdx == 6) {
            return (orig & empty7) | index7 | shiftLeft(val, 48);
        } else
        if (currIdx == 7) {
            return (orig & empty8) | index8 | shiftLeft(val, 24);
        } else
        if (currIdx == 8) {
            return (orig & empty9) | index9 | val;
        }
    }

    function setFees(uint128 _contentPartFee, uint128 _recipientFee) public onlyOwner {
        contentPartFee = _contentPartFee;
        recipientFee = _recipientFee;
    }

    function setBeneficiary(address payable _beneficiary) public onlyOwner {
        beneficiary = _beneficiary;
    }

    function buildHash(uint256 senderAddress, uint32 uniqueId, uint32 time) public pure returns (uint256 _hash) {
        bytes memory data = bytes.concat(bytes32(senderAddress), bytes4(uniqueId), bytes4(time));
        _hash = uint256(sha256(data));
    }

    // Virtual function for initializing bulk message sending
    function getMsgId(uint256 senderAddress, uint32 uniqueId, uint32 initTime) public pure returns (uint256 msgId) {
        msgId = buildHash(senderAddress, uniqueId, initTime);
    }

    // Send part of the long message
    function sendMultipartMailPart(uint32 uniqueId, uint32 initTime, uint16 parts, uint16 partIdx, bytes calldata content) public {
        if (block.timestamp < initTime) {
            revert();
        }
        if (block.timestamp - initTime >= 600) {
            revert();
        }

        uint256 msgId = buildHash(uint256(uint160(msg.sender)), uniqueId, initTime);

        emit MailContent(msgId, msg.sender, parts, partIdx, content);

        if (contentPartFee > 0) {
            beneficiary.transfer(contentPartFee);
        }
    }

    // Add recipient keys to some message
    function addRecipients(uint32 uniqueId, uint32 initTime, uint256[] calldata recipients, bytes[] calldata keys) public {
        uint256 msgId = buildHash(uint256(uint160(msg.sender)), uniqueId, initTime);
        for (uint i = 0; i < recipients.length; i++) {
            uint256 current = recipientToPushIndex[recipients[i]];
            recipientToPushIndex[recipients[i]] = nextIndex(current, block.number / 128);
            recipientMessagesCount[recipients[i]] += 1;
            emit MailPush(recipients[i], msg.sender, msgId, current, keys[i]);
        }

        if (recipientFee * recipients.length > 0) {
            beneficiary.transfer(uint128(recipientFee * recipients.length));
        }
    }

    function sendSmallMail(uint32 uniqueId, uint256 recipient, bytes calldata key, bytes calldata content) public {
        uint256 msgId = buildHash(uint256(uint160(msg.sender)), uniqueId, uint32(block.timestamp));

        emit MailContent(msgId, msg.sender, 1, 0, content);
        uint256 current = recipientToPushIndex[recipient];
        recipientToPushIndex[recipient] = nextIndex(current, block.number / 128);
        recipientMessagesCount[recipient] += 1;
        emit MailPush(recipient, msg.sender, msgId, current, key);

        if (contentPartFee + recipientFee > 0) {
            beneficiary.transfer(uint128(contentPartFee + recipientFee));
        }
    }

    function sendBulkMail(uint32 uniqueId, uint256[] calldata recipients, bytes[] calldata keys, bytes calldata content) public {
        uint256 msgId = buildHash(uint256(uint160(msg.sender)), uniqueId, uint32(block.timestamp));

        emit MailContent(msgId, msg.sender, 1, 0, content);

        for (uint i = 0; i < recipients.length; i++) {
            uint256 current = recipientToPushIndex[recipients[i]];
            recipientToPushIndex[recipients[i]] = nextIndex(current, block.number / 128);
            recipientMessagesCount[recipients[i]] += 1;
            emit MailPush(recipients[i], msg.sender, msgId, current, keys[i]);
        }

        if (contentPartFee + recipientFee * recipients.length > 0) {
            beneficiary.transfer(uint128(contentPartFee + recipientFee * recipients.length));
        }
    }

    function broadcastMail(uint32 uniqueId, bytes calldata content) public {
        uint256 msgId = buildHash(uint256(uint160(msg.sender)), uniqueId, uint32(block.timestamp));

        emit MailContent(msgId, msg.sender, 1, 0, content);
        uint256 current = senderToBroadcastIndex[msg.sender];
        senderToBroadcastIndex[msg.sender] = nextIndex(current, block.number / 128);
        broadcastMessagesCount[msg.sender] += 1;
        emit MailBroadcast(msg.sender, msgId, current);

        if (contentPartFee > 0) {
            beneficiary.transfer(uint128(contentPartFee));
        }
    }

    function broadcastMailHeader(uint32 uniqueId, uint32 initTime) public {
        uint256 msgId = buildHash(uint256(uint160(msg.sender)), uniqueId, initTime);
        uint256 current = senderToBroadcastIndex[msg.sender];
        senderToBroadcastIndex[msg.sender] = nextIndex(current, block.number / 128);
        broadcastMessagesCount[msg.sender] += 1;
        emit MailBroadcast(msg.sender, msgId, current);
    }
}