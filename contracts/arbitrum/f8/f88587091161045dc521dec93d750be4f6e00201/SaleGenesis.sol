// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ECDSA.sol";
import "./IGenesisNFT.sol";

contract SaleGenesis is Ownable, ReentrancyGuard {
    using Address for address payable;
    using SafeERC20 for IERC20;

    uint public constant maxSaleGenesisNumber = 2000;
    IGenesisNFT public genesisNFT;
    IERC20 public usdcToken;

    address public signAddress;
    uint public startTime;
    uint public endTime;
    uint public price = 900e6;
    address public treasuryAddress;

    uint public mintCounter;
    mapping(address => uint) public userMintNumber;

    event WhitelistBuy(address sender, uint payAmount);
    event MintToVault(address sender, address treasuryAddress, uint num);

    constructor(
        uint _startTime,
        uint _endTime,
        address _genesisNFT,
        address _usdcToken
    ){
        startTime = _startTime;
        endTime = _endTime;
        genesisNFT = IGenesisNFT(_genesisNFT);
        usdcToken = IERC20(_usdcToken);
        treasuryAddress = 0x7FcA3BF8AdC4e143BD789AecDa36c0CE34f1d75B;
        signAddress = 0x222dcf1720c36248B7C1A5b60268A8c5f1E4b85A;
    }

    function setUsdcToken(address _usdcToken) external onlyOwner {
        usdcToken = IERC20(_usdcToken);
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        require(_treasuryAddress != address(0), 'invalid address');
        treasuryAddress = _treasuryAddress;
    }

    function setSignAddress(address _signAddress) external onlyOwner {
        require(_signAddress != address(0), 'invalid address');
        signAddress = _signAddress;
    }

    function mintToVault(uint num) external onlyOwner {
        require(endTime < block.timestamp, 'unfinished');
        require(mintCounter < maxSaleGenesisNumber, 'sold out');
        if (mintCounter + num > maxSaleGenesisNumber) {
            num = maxSaleGenesisNumber - mintCounter;
        }
        mintCounter += num;
        genesisNFT.mint(treasuryAddress, num);
        emit MintToVault(msg.sender, treasuryAddress, num);
    }

    function whitelistMint(bytes memory signature) external nonReentrant {
        require(startTime <= block.timestamp, 'not started');
        require(endTime >= block.timestamp, 'finished');
        require(mintCounter < maxSaleGenesisNumber, 'sold out');
        require(userMintNumber[msg.sender] == 0, 'already');

        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(msg.sender, block.chainid, address(this))));
        address recoverAddress = ECDSA.recover(hash, signature);
        require(recoverAddress == signAddress, 'Invalid Signed Message');

        usdcToken.safeTransferFrom(msg.sender, treasuryAddress, price);
        userMintNumber[msg.sender] = 1;
        genesisNFT.mint(msg.sender, 1);
        mintCounter++;

        emit WhitelistBuy(msg.sender, price);
    }

    function getStatusInfo() public view returns (uint startTime_, uint endTime_, uint price_, uint mintCounter_){
        startTime_ = startTime;
        endTime_ = endTime;
        price_ = price;
        mintCounter_ = mintCounter;
    }
}

