// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./SignatureChecker.sol";

import "./Math.sol";
import "./Strings.sol";

import "./ECDSA.sol";

contract DistributionPool is OwnableUpgradeable {
    uint256 public constant MAX_ADDRESSES = 625143;
    uint256 public constant MAX_TOKEN = 20000000000000 * 10**6;
    uint256 public constant INIT_CLAIM = 123047619 * 10**6;
    address public signer = 0x30d8E2f3D2a18b0AE7BCE81789B48c4B7f6263D4;
    struct InfoView {
        uint256 maxToken;
        uint256 initClaim;
        uint256 currentClaim;
        bool claimed;
        uint256 inviteRewards;
        uint256 inviteUsers;
        uint256 claimedSupply;
        uint256 claimedCount;
    }

    event Claim(
        address indexed user,
        uint128 nonce,
        uint256 amount,
        address referrer,
        uint256 timestamp
    );

    IERC20 public token;

    mapping(uint256 => bool) public _usedNonce;
    mapping(address => bool) public _claimedUser;
    mapping(address => uint256) public inviteRewards;

    uint256 public claimedSupply = 0;
    uint256 public claimedCount = 0;
    uint256 public claimedPercentage = 0;
    mapping(address => uint256) public inviteUsers;

    function initialize(address token_) external initializer {
        __Ownable_init();
        token = IERC20(token_);
    }

    function canClaimAmount() public view returns (uint256) {
        if (claimedCount >= MAX_ADDRESSES) {
            return 0;
        }

        uint256 supplyPerAddress = INIT_CLAIM;
        uint256 curClaimedCount = claimedCount + 1;
        uint256 claimedPercent = (curClaimedCount * 100e6) / MAX_ADDRESSES;
        uint256 curPercent = 5e6;

        while (curPercent <= claimedPercent) {
            supplyPerAddress = (supplyPerAddress * 80) / 100;
            curPercent += 5e6;
        }

        return supplyPerAddress;
    }

    function claim(
        uint128 nonce,
        bytes calldata signature,
        address referrer
    ) public {
        require(_usedNonce[nonce] == false, "nonce already used");
        require(_claimedUser[_msgSender()] == false, "already claimed");
        address sender=msg.sender;
        bool sig = verifySignature(sender, nonce, signature);
        if (sig) {
            _usedNonce[nonce] = true;
            _claimedUser[_msgSender()] = true;

            uint256 supplyPerAddress = canClaimAmount();
            require(supplyPerAddress >= 1e6, "Airdrop has ended");

            uint256 amount = canClaimAmount();
            token.transfer(_msgSender(), amount);

            claimedCount++;
            claimedSupply += supplyPerAddress;

            if (claimedCount > 0) {
                claimedPercentage = (claimedCount * 100) / MAX_ADDRESSES;
            }

            if (referrer != address(0) && referrer != _msgSender()) {
                uint256 num = (amount * 100) / 1000;
                token.transfer(referrer, num);
                inviteRewards[referrer] += num;
                inviteUsers[referrer]++;
            }

            emit Claim(_msgSender(), nonce, amount, referrer, block.timestamp);
        }
    }

    function getInfoView(address user) public view returns (InfoView memory) {
        return
            InfoView({
                maxToken: MAX_TOKEN,
                initClaim: INIT_CLAIM,
                currentClaim: canClaimAmount(),
                claimed: _claimedUser[user],
                inviteRewards: inviteRewards[user],
                inviteUsers: inviteUsers[user],
                claimedSupply: claimedSupply,
                claimedCount: claimedCount
            });
    }

    function setSigner(address val) public onlyOwner {
        require(val != address(0), "SmallDog: val is the zero address");
        signer = val;
    }

    function verifySignature(
        address sender,
        uint256 nonce,
        bytes calldata signature
    ) private view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(sender, nonce));
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        address receivedAddress = ECDSA.recover(message, signature);
        require(receivedAddress != address(0));
        if (receivedAddress == signer) {
            return true;
        } else {
            return false;
        }
    }
}

