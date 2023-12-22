/**

   _____ _     _ _     _____          ____  
  / ____| |   (_) |   |  __ \   /\   / __ \ 
 | (___ | |__  _| |__ | |  | | /  \ | |  | |
  \___ \| '_ \| | '_ \| |  | |/ /\ \| |  | |
  ____) | | | | | |_) | |__| / ____ \ |__| |
 |_____/|_| |_|_|_.__/|_____/_/    \_\____/ 

    Website: https://shibariumdao.io
    Telegram: https://t.me/ShibariumDAO

**/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AccessControl.sol";
import "./IERC20.sol";
import "./Counters.sol";
import "./ECDSA.sol";
import "./EIP712.sol";

contract PortShibBridge is EIP712, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 private constant _BRIDGE_PERMIT_TYPEHASH =
        keccak256("BridgePermit(uint256 nonce,address to,uint256 amount,uint256 deadline)");

    mapping(uint256 => bool) public bridgeNoncesUsed;
    Counters.Counter private _returnNonce;

    IERC20 public immutable TOKEN;

    event Bridge(uint256 bridgeNonce, address to, uint256 amount);
    event Return(uint256 returnNonce, address from, uint256 amount);

    constructor(address token_) EIP712("PortShibBridge", "1") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        TOKEN = IERC20(token_);
    }

    function bridgeTokens(
        uint256 bridgeNonce,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 structHash = keccak256(
            abi.encode(_BRIDGE_PERMIT_TYPEHASH, bridgeNonce, to, amount, deadline)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);

        require(
            !bridgeNoncesUsed[bridgeNonce],
            "PortShibBridge: nonce already used"
        );
        require(
            hasRole(BRIDGE_ROLE, signer),
            "PortShibBridge: invalid signer"
        );
        require(
            block.timestamp <= deadline,
            "PortShibBridge: permit expired"
        );

        bridgeNoncesUsed[bridgeNonce] = true;

        bool success = TOKEN.transfer(to, amount);
        require(success, "PortShibBridge: transfer failed");

        emit Bridge(bridgeNonce, to, amount);
    }

    function returnTokens(uint256 amount) external returns (uint256) {
        _returnNonce.increment();
        uint256 returnNonce = _returnNonce.current();

        bool success = TOKEN.transferFrom(msg.sender, address(this), amount);
        require(success, "PortShibBridge: transfer failed");

        emit Return(returnNonce, msg.sender, amount);

        return returnNonce;
    }

    function clearBalance(address token, uint256 amount) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "PortShibBridge: must have admin role to clear balance"
        );

        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "PortShibBridge: transfer failed");
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}

