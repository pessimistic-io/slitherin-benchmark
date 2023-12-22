// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SignatureChecker.sol";

contract RektDistributor is Ownable {
    using ECDSA for bytes32;  

    IERC20 public token;

    address public signer;

    uint256 public constant MAX_ADDRESSES = 625_143;
    uint256 public constant INIT_CLAIM = 416_800_000 * 1e6;
    uint256 public constant MAX_REFER_TOKEN = 4_200_000_000_000 * 1e6;

    mapping(uint256 => bool) public _usedNonce;
    mapping(address => bool) public _claimedUser;
    mapping(address => uint256) public inviteRewards;

    uint256 public claimedSupply = 0;
    uint256 public claimedCount = 0;
    uint256 public claimedPercentage = 0;

    mapping(address => uint256) public inviteUsers;

    uint256 public referReward = 0;

    event Claim(address indexed user, uint128 nonce, uint256 amount, address referrer, uint timestamp);

    function canClaimAmount() public view returns(uint256) {
        if (_claimedUser[_msgSender()]) {
            return 0;
        }

        if (claimedCount >= MAX_ADDRESSES) {
            return 0;
        }

        uint256 supplyPerAddress = INIT_CLAIM;
        uint256 curClaimedCount = claimedCount + 1;
        uint256 claimedPercent = curClaimedCount * 100e6 / MAX_ADDRESSES;
        uint256 curPercent = 5e6;

        while (curPercent <= claimedPercent) {
            supplyPerAddress = (supplyPerAddress * 80) / 100;
            curPercent += 5e6;
        }

        return supplyPerAddress;
    }

    function claim(uint128 nonce, bytes calldata signature, address referrer) public {
        require(_usedNonce[nonce] == false, "Rekt: nonce already used");
        require(_claimedUser[_msgSender()] == false, "Rekt: already claimed");

        _claimedUser[_msgSender()] = true;
        require(isValidSignature(nonce, signature), "Rekt: only auth claims");
        
        _usedNonce[nonce] = true;

        uint256 supplyPerAddress = canClaimAmount();
        require(supplyPerAddress >= 1e6, "Rekt: airdrop has ended");

        uint256 amount = canClaimAmount();
        token.transfer(_msgSender(), amount);

        claimedCount++;
        claimedSupply += supplyPerAddress;

        if (claimedCount > 0) {
            claimedPercentage = (claimedCount * 100) / MAX_ADDRESSES;
        }

        if (referrer != address(0) && referrer != _msgSender() && referReward < MAX_REFER_TOKEN) {
            uint256 num = amount * 100 / 1000;
            token.transfer(referrer, num);
            inviteRewards[referrer] += num;
            inviteUsers[referrer]++;

            referReward += num;
        }

        emit Claim(_msgSender(), nonce, amount, referrer, block.timestamp);
    }

    function setSigner(address val) public onlyOwner() {
        require(val != address(0), "Rekt: val is the zero address");
        signer = val;
    }

    function setToken(address _tokenAddress) public onlyOwner() {
        token = IERC20(_tokenAddress);
    }

    function isValidSignature(
        uint128 nonce,
        bytes memory signature
    ) view internal returns (bool) {
        bytes32 data = keccak256(abi.encode(address(this), _msgSender(), nonce));
        return signer == data.toEthSignedMessageHash().recover(signature);
    }
}
