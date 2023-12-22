// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Address.sol";
import "./AccessControl.sol";
import "./Pausable.sol";

import "./IBridgeToken.sol";


contract Bridge is AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 private constant FEE_DENOMINATOR = 10000; // 0.01[%]

    enum Step { Burn, Mint }

    uint256 private fee;
    IBridgeToken public token;
    address public feeReceiver;

    mapping(address => mapping(uint => bool)) public processedTransactions;

    event Transfer(
		address from,
		address to,
		uint amount,
		uint date,
		uint nonce,
		bytes signature,
		Step indexed step
	);

    constructor() {
        address _defaultAdmin = _msgSender();
        // ACL configs
        _grantRole(ADMIN_ROLE, _defaultAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        // Default fee
        fee = 20; // Default: 0.2%[%]
        _pause();
    }

    function burn(address to, uint amount, uint nonce, bytes calldata signature) external whenNotPaused {
        address sender = msg.sender;
		require(processedTransactions[sender][nonce] == false, 'transfer already processed');
        require(address(token) != address(0), 'invalid token');

        // Take bridge fee
        uint256 fees = (amount * fee) / FEE_DENOMINATOR;
        uint256 netAmount = amount - fees;

		processedTransactions[sender][nonce] = true;
		token.deposit(sender, netAmount);
		emit Transfer(sender, to, netAmount, block.timestamp, nonce, signature, Step.Burn);
	}

    function mint(address from, address to, uint amount, uint nonce, bytes calldata signature ) external whenNotPaused {
		bytes32 message = prefixed(keccak256(abi.encodePacked(from, to, amount, nonce )));

        require(address(token) != address(0), 'invalid token');
		require(recoverSigner(message, signature) == from , 'wrong signature');
		require(processedTransactions[from][nonce] == false, 'transfer already processed');       

		processedTransactions[from][nonce] = true;
		token.withdraw(to, amount);
		emit Transfer(from, to, amount, block.timestamp, nonce, signature, Step.Mint);
	}

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
		return keccak256(abi.encodePacked(
			'\x19Ethereum Signed Message:\n32',
			hash
		));
	}

    function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {
		uint8 v;
		bytes32 r;
		bytes32 s;
		(v, r, s) = splitSignature(sig);
		return ecrecover(message, v, r, s);
	}

    function splitSignature(bytes memory sig) internal pure returns (uint8, bytes32, bytes32) {
		require(sig.length == 65);
		bytes32 r;
		bytes32 s;
		uint8 v;
		assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
		}
		return (v, r, s);
	}

    function setToken(address _token) external onlyRole(ADMIN_ROLE) {
        token = IBridgeToken(_token);
    }

    function setFeeReceiver(address receiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = receiver;
    }

    function setFee(uint256 percentage) external onlyRole(ADMIN_ROLE) { 
        require(percentage < 100, "too high"); // No more than 1[%]
        fee = percentage;
    }

    function openGateway(address _token) external onlyRole(ADMIN_ROLE) whenPaused {
        _unpause();
    }

    function closeGateway() external onlyRole(ADMIN_ROLE) whenNotPaused {
        _pause();
    }

    function updateAdmin(address _admin) public onlyRole(ADMIN_ROLE) {
        _grantRole(ADMIN_ROLE, _admin);
    }
}
