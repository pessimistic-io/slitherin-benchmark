// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ECDSA.sol";
import "./ReentrancyGuard.sol";

/// @notice Ryze reward distributor
contract RyzeDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /// @notice Emitted when claimed token
    /// @param user user address
    /// @param amount claimed amount
    event Claimed(address indexed user, uint256 amount);

    address private constant ETH =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice claimed amount per token. user => claimed amount
    mapping(address => uint256) public claimedAmount;

    /// @notice signer address
    address public signer;

    /// underlying token
    address public underlyingToken;

    /// treasury wallet for referrals
    address public treasuryReferrals;

    constructor(
        address _signer,
        address _underlyingToken,
        address _treasuryReferrals
    ) {
        signer = _signer;
        underlyingToken = _underlyingToken;
        treasuryReferrals = _treasuryReferrals;
    }

    /// @notice Update signer
    /// @param _signer signer address
    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Invalid address");
        signer = _signer;
    }

    /// @notice Update underlying token
    /// @param _underlyingToken underlyingToken address
    function setUnderlyingToken(address _underlyingToken) external onlyOwner {
        require(_underlyingToken != address(0), "Invalid address");
        underlyingToken = _underlyingToken;
    }

    function setTreasuryReferralWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "Invalid address");
        treasuryReferrals = _wallet;
    }

    /// @notice Claim available amount through merkle tree
    /// @param allocation total allocation
    /// @param signature signature from backend
    function claim(uint256 allocation, bytes calldata signature)
        external
        nonReentrant
    {
        require(
            verifySigner(msg.sender, allocation, signature),
            "invalid signature"
        );

        if (allocation > claimedAmount[msg.sender]) {
            uint256 availableAmount = allocation - claimedAmount[msg.sender];
            if (availableAmount != 0) {
                claimedAmount[msg.sender] = allocation;

                // Transfer token from treasury to msg.sender
                IERC20(underlyingToken).safeTransferFrom(
                    treasuryReferrals,
                    msg.sender,
                    availableAmount
                );

                emit Claimed(msg.sender, availableAmount);
            }
        }
    }

    /// @dev recover tokens by owner
    function recoverToken(address token, uint256 amount) external onlyOwner {
        if (token == ETH) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ether transfer failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function verifySigner(
        address sender,
        uint256 fee,
        bytes calldata signature
    ) public view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(sender, fee));
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        address signedAddress = ECDSA.recover(message, signature);
        return signedAddress != address(0) && signedAddress == signer;
    }

    receive() external payable {}
}

