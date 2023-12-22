// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SignatureChecker.sol";

contract BruhDistributor is Ownable {
    using ECDSA for bytes32;

    IERC20 public token;

    address public signer;

    uint256 public constant MAX_ADDRESSES = 636_836;
    uint256 public constant MAX_TOKEN = 12_420_000_000_000 * 1e6;
    uint256 public constant INIT_CLAIM = 78_992_000 * 1e6;

    uint256 public constant MAX_REFER_TOKEN = 1_242_000_000_000 * 1e6;

    mapping(uint256 => bool) public _usedNonce;
    mapping(address => bool) public _claimedUser;
    mapping(address => uint256) public inviteRewards;

    uint256 public claimedSupply = 0;
    uint256 public claimedCount = 0;
    uint256 public claimedPercentage = 0;
    uint256 public endTime;

    mapping(address => uint256) public inviteUsers;

    bool public isStarted;
    uint256 public referReward = 0;

    event Claim(address indexed user, uint128 nonce, uint256 amount, address referrer, uint timestamp);
    event Start(address token, uint256 startTime, uint256 endTime);

    function canClaimAmount() public view returns(uint256) {
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

    function claim(uint128 nonce, bytes calldata signature, address referrer) external {
        require(isStarted, "BRUH: claim not started");
        require(_usedNonce[nonce] == false, "BRUH: nonce already used");
        require(_claimedUser[_msgSender()] == false, "BRUH: already claimed");

        _claimedUser[_msgSender()] = true;
        require(isValidSignature(nonce, signature), "BRUH: only auth claims");

        _usedNonce[nonce] = true;

        uint256 supplyPerAddress = canClaimAmount();
        require(supplyPerAddress >= 1e6, "BRUH: airdrop has ended");

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

    function setSigner(address val) external onlyOwner() {
        require(val != address(0), "BRUH: val is the zero address");
        signer = val;
    }

    function start(address _tokenAddress) external onlyOwner() {
        require(signer != address(0), "BRUH: set singer before start");
        require(!isStarted, "BRUH: already started");
        token = IERC20(_tokenAddress);
        token.transferFrom(msg.sender, address(this), (MAX_TOKEN+MAX_REFER_TOKEN));
        endTime = block.timestamp + 30 days;
        isStarted = true;

        emit Start(_tokenAddress, block.timestamp, endTime);
    }

    function isValidSignature(
        uint128 nonce,
        bytes memory signature
    ) view internal returns (bool) {
        bytes32 data = keccak256(abi.encodePacked(address(this), _msgSender(), nonce));//
        return signer == data.toEthSignedMessageHash().recover(signature);
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        if (_token != address(0)) {
            if (_token == address(this)) {
                require(block.timestamp >= endTime, "BRUH: claim not ended");
            }
			IERC20(_token).transfer(msg.sender, _amount);
		} else {
			(bool success, ) = payable(msg.sender).call{ value: _amount }("");
			require(success, "Can't send ETH");
		}
	}
}
