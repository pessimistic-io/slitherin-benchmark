// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./ECDSA.sol";
import "./IArbSys.sol";

contract CheeseAirdrop is Ownable {
    using ECDSA for bytes32;

    // 1: 0 ETH
    // 2: 0.001 ARB
    // 4: 0.001 MARGIC
    // 8: 1 MEMECOIN
    // 16: ETH Power
    // 32: ARB Power
    // 64: MARGIC Power
    // 128: RICE Power
    // 256: MEMECOIN TOP1 Power
    // 512: MEMECOIN TOP2 Power
    // 1024: MEMECOIN TOP3 Power
    // 2048: Liquid donation
    // 4096: ARB Claimer
    mapping(address => uint256) public claimedUser;

    uint256 public claimedSupply = 0;
    uint256 public claimedCount = 0;
    uint256 public arbClaimerCount = 0;
    uint256 public referrerSupply = 0;
    uint256 public maxReferrerSupply = 210_000_000_000_000_000 * 1e4 * 5;

    ERC20 public immutable cheese;

    event Claim(
        address indexed user,
        uint256 indexed tag,
        uint256 amount,
        uint timestamp
    );

    constructor(ERC20 cheese_) {
        cheese = cheese_;
    }

    function claim(
        bytes calldata signature,
        uint256 tag,
        uint256 amount,
        address referrer
    ) public {
        address msgSender = _msgSender();
        require(claimedUser[msgSender] == 0, "already claimed");
        claimedUser[msgSender] = tag;

        bytes32 message = keccak256(
            abi.encodePacked(
                address(this),
                msgSender,
                tag,
                amount,
                referrer,
                "claim"
            )
        );
        require(
            message.toEthSignedMessageHash().recover(signature) == owner(),
            "Invalid signature"
        );

        claimedCount++;
        if (tag >= 4096) {
            arbClaimerCount++;
            require(arbClaimerCount <= 20000, "ARB Claimer limit");
        }

        cheese.transfer(msgSender, amount);
        claimedSupply += amount;

        if (maxReferrerSupply > referrerSupply) {
            if (referrer != address(0) && referrer != msgSender) {
                uint256 referrerAmount = amount / 10;
                cheese.transfer(referrer, referrerAmount);
                referrerSupply += referrerAmount;
            }
        }

        emit Claim(msgSender, tag, amount, block.timestamp);
    }

    function back(uint256 amount) public onlyOwner {
        cheese.transfer(owner(), amount);
    }
}

