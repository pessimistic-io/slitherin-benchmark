// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./Strings.sol";
import "./SignatureChecker.sol";

interface IMint {
    function keys(address account) external view returns (uint256);
}

contract Pool is Ownable {
    uint256 public constant BASE = 10000;
    address public immutable usdt;
    address public immutable mint;

    address public signer;
    uint256 public totalReward;

    mapping(address => uint256) public useKeys;

    event Opened(address indexed accout, uint256 amount);

    error Forbidden();
    error InvalidSignature();

    constructor(address _usdt, address _mint) {
        usdt = _usdt;
        mint = _mint;

        signer = msg.sender;
    }

    function setSigner(address newSigner) public onlyOwner {
        signer = newSigner;
    }

    function open(uint256 seed, uint256[] memory challenges, uint256[] memory rewards, bytes memory signature) public {
        if (Address.isContract(msg.sender)) revert Forbidden();

        bytes memory message = abi.encode(seed, challenges, rewards);
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(bytes(message).length), message)
        );
        if (SignatureChecker.isValidSignatureNow(signer, hash, signature) == false) revert InvalidSignature();

        if (IMint(mint).keys(msg.sender) - useKeys[msg.sender] == 0) revert Forbidden();
        useKeys[msg.sender]++;

        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, seed))) % BASE;
        for (uint i = 0; i < challenges.length; i++) {
            if (random <= challenges[i]) {
                uint256 reward = (IERC20(usdt).balanceOf(address(this)) * rewards[i]) / BASE;
                IERC20(usdt).transfer(msg.sender, reward);
                totalReward += reward;
                emit Opened(msg.sender, reward);
                return;
            }
        }
    }

    function claim(address token, address to, uint256 amount) public onlyOwner {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).transfer(to, amount);
        }
    }
}

