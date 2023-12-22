// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC20PermitUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";

contract SCRDS is OwnableUpgradeable, PausableUpgradeable, ERC20PermitUpgradeable {
    using ECDSAUpgradeable for bytes32;

    // exchange signer address
    address public verifierAddress;
    // deadline to exchange sCRDS
    uint public deadline;
    // nonce for each exchanger in case of double exchange with one signature
    mapping(address => uint) public exchangerNonces;

    event DeadlineChanged(uint deadline, uint preDeadline);
    event VerifierAddressChanged(address verifierAddress, address preVerifierAddress);
    event Exchange(address exchanger, uint amount, uint nonce);

    function __SCRDS_init(string memory name, string memory symbol, address newVerifierAddress, uint newDeadline) external initializer() {
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __ERC20Permit_init(name);
        __ERC20_init_unchained(name, symbol);
        verifierAddress = newVerifierAddress;
        deadline = newDeadline;
    }

    function exchange(uint amount, uint timestamp, bytes calldata signature) external whenNotPaused {
        uint currentTimestamp = block.timestamp;
        require(currentTimestamp < deadline, "expired");
        require(currentTimestamp - timestamp <= 6 minutes, "invalid timestamp");
        address sender = msg.sender;
        uint currentNonce = exchangerNonces[sender];
        exchangerNonces[sender] = currentNonce + 1;

        // verify signature
        require(
            verifierAddress == keccak256(
            abi.encodePacked(
                amount,
                sender,
                currentNonce,
                timestamp
            )
        ).toEthSignedMessageHash().recover(signature),
            "invalid sig"
        );
        // mint token
        _mint(sender, amount);

        emit Exchange(sender, amount, currentNonce);
    }

    function setDeadline(uint newTimestamp) external onlyOwner {
        uint preDeadline = deadline;
        deadline = newTimestamp;
        emit DeadlineChanged(newTimestamp, preDeadline);
    }

    function setVerifierAddress(address newVerifierAddress) external onlyOwner {
        address preVerifierAddress = verifierAddress;
        verifierAddress = newVerifierAddress;
        emit VerifierAddressChanged(newVerifierAddress, preVerifierAddress);
    }

    function flipPause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }

    uint[47] __gap;
}

