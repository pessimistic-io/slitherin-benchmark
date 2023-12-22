// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./ECDSA.sol";

contract Mixer is ReentrancyGuard {
    struct Deposit {
        uint256 amount;
        address tokenAddress;
    }

    mapping(bytes32 => Deposit) public deposits;

    // Usdc Address-->0xe9DcE89B076BA6107Bb64EF30678efec11939234
    // User deposit tokens to the contract
    function deposit(
        address userAddress,
        address token,
        uint256 amount,
        bytes32 commitment
    ) external {
        require(
            deposits[commitment].amount == 0,
            "This commitment has been used"
        );

        IERC20 tokenContract = IERC20(token);
        // transfer tokens to contract
        tokenContract.transferFrom(userAddress, address(this), amount);

        // store the deposit data
        deposits[commitment] = Deposit(amount, token);
    }

    // User withdraw tokens from the contract
    function withdraw(
        bytes32 commitment,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address payable to
    ) external nonReentrant {
        Deposit memory depositData = deposits[commitment];
        require(depositData.amount > 0, "Invalid commitment");

        // verify signature
        bytes32 message = prefixed(keccak256(abi.encodePacked(to, commitment)));
        require(ecrecover(message, v, r, s) == to, "Invalid signature");

        // transfer tokens
        IERC20 tokenContract = IERC20(depositData.tokenAddress);
        tokenContract.transfer(to, depositData.amount);

        // zero out the deposit data
        delete deposits[commitment];
    }

    // internal function to prefix a string
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }
}

