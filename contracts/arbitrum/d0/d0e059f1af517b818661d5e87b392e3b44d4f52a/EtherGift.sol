// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ECDSA.sol";
import "./Strings.sol";

contract EtherGift {
    using SafeERC20 for IERC20;

    struct redPacketStruct {
        address creator;
        address tokenAddress;
        uint256 amount;
        uint16 peopleCount;
        bool isAverage;
        string creatorTwitter;
        string[] crowd;
        address publicAddress;
        uint64 expiration;
        mapping(address => bool) addressOpen;
        mapping(string => bool) twitterOpen;
    }

    struct createParameter{
        address tokenAddress;
        uint256 amount;
        uint16 peopleCount;
        bool isAverage;
        string creatorTwitter;
        string[] crowd;
        address publicAddress;
        uint32 identifier;
        uint64 expiration;
    }

    mapping(uint32 => redPacketStruct) private _redPackets;
    mapping(address => uint256) public tips;

    event Create(address sender,uint32 identifer);
    event Open(address opener,uint256 amount,address tokenAddress);
    event Withdraw(address sender, uint32 identifer, uint256 amount);

    address authAddress = 0xe7aEAA4713B0a29a6Aa5f2F9e464a01A5304fA9f;

    function create(createParameter memory parameter,bytes calldata signature) external payable {
        require(msg.sender == tx.origin, "The contract cannot be called");
        require(_verifySignature(Strings.toHexString(parameter.publicAddress), signature) == authAddress,"Not approved");
        require(_redPackets[parameter.identifier].creator == address(0),"Identifier is used");
        require(parameter.peopleCount > 0, "PeopleCount has to be greater than 0");
        require(parameter.publicAddress != address(0), "Public address can not be nill");
        require(parameter.expiration <= 604800,"It can only be within 7 days");

        uint256 tip = parameter.amount / 100;
        uint256 total = parameter.amount + tip;

        require(parameter.amount >= parameter.peopleCount, "The amount must be greater than the number of people");

        if (parameter.tokenAddress == address(0)) {
            require(total == msg.value, "Insufficient amount");
        } else {
            IERC20(parameter.tokenAddress).safeTransferFrom(msg.sender,address(this),total);
        }

        tips[parameter.tokenAddress] += tip;

        redPacketStruct storage r = _redPackets[parameter.identifier];
        r.creator = msg.sender;
        r.tokenAddress = parameter.tokenAddress;
        r.amount = parameter.amount;
        r.peopleCount = parameter.peopleCount;
        r.isAverage = parameter.isAverage;
        r.creatorTwitter = parameter.creatorTwitter;
        r.crowd = parameter.crowd;
        r.publicAddress = parameter.publicAddress;
        r.expiration = uint64(block.timestamp) + parameter.expiration;

        emit Create(msg.sender,parameter.identifier);
    }

    function open(uint32 identifier,string memory userTwitter,bytes calldata signature) external {
        require(msg.sender == tx.origin, "The contract cannot be called");
        redPacketStruct storage redPacket = _redPackets[identifier];
        require(_verifySignature(userTwitter, signature) == redPacket.publicAddress,"Not approved");
        require(redPacket.creator != address(0),"Does not exist");
        require(block.timestamp < redPacket.expiration, "Past due");
        require(redPacket.peopleCount > 0, "No place");
        require(redPacket.addressOpen[msg.sender] == false && redPacket.twitterOpen[userTwitter] == false,"Can only be opened once");

        uint256 amount;
        if (redPacket.peopleCount == 1){
            amount = redPacket.amount;
        }
        else{
            require(redPacket.peopleCount <= redPacket.amount);
            if(redPacket.isAverage){
                amount = redPacket.amount / redPacket.peopleCount;
            }
            else{
                amount = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, block.number, msg.sender))) % (redPacket.amount / redPacket.peopleCount * 2 - 1) + 1;
            }
        }

        require(amount <= redPacket.amount, "No amount");

        redPacket.amount -= amount;
        redPacket.peopleCount -= 1;
        redPacket.addressOpen[msg.sender] = true;
        redPacket.twitterOpen[userTwitter] = true;

        _send(redPacket.tokenAddress, amount, msg.sender);

        emit Open(msg.sender, amount, redPacket.tokenAddress);
    }

    function _verifySignature(string memory _text, bytes calldata _signature) private pure returns (address){
        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(_text))
        );
        address receivedAddress = ECDSA.recover(message, _signature);
        return receivedAddress;
    }

    function user_withdraw(uint32 identifier) external {
        require(msg.sender == tx.origin, "The contract cannot be called");
        redPacketStruct storage redPacket = _redPackets[identifier];
        require(redPacket.creator == msg.sender, "Not creator");
        require(block.timestamp > redPacket.expiration, "not out of date");
        require(redPacket.amount > 0, "No amount");

        uint256 amount = redPacket.amount;
        redPacket.amount = 0;
        redPacket.peopleCount = 0;

        _send(redPacket.tokenAddress, amount, redPacket.creator);

        emit Withdraw(msg.sender,identifier,amount);
    }

    function info(uint32 identifier) external view returns (address,address,uint256,uint16,bool,string memory,string[] memory,address,uint64){
        redPacketStruct storage redPacket = _redPackets[identifier];
        return (
            redPacket.creator,
            redPacket.tokenAddress,
            redPacket.amount,
            redPacket.peopleCount,
            redPacket.isAverage,
            redPacket.creatorTwitter,
            redPacket.crowd,
            redPacket.publicAddress,
            redPacket.expiration
        );
    }

    function is_open(uint32 identifier,address _address,string memory userTwitter) public view returns(bool,bool){
        redPacketStruct storage redPacket = _redPackets[identifier];
        return (redPacket.addressOpen[_address],redPacket.twitterOpen[userTwitter]);
    }

    function _send(address _tokenAddress,uint256 _amount,address _to) private {
        require(_amount > 0,"Amount must greater than 0");
        if (_tokenAddress == address(0)) {
            payable(_to).transfer(_amount);
        } else {
            IERC20(_tokenAddress).safeTransfer(_to, _amount);
        }
    }

    function own_withdraw(address tokenAddress,uint256 tip) external {
        require(tip != 0, "no tip");
        require(tip <= tips[tokenAddress],"Not enough tip");

        _send(tokenAddress, tip, 0xc9B383092e282A16fc033B75aFFB2B472b86D609);
    }
}
