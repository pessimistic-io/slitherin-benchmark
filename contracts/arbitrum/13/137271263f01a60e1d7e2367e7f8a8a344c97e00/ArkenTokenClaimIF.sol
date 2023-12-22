// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.16;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./draft-EIP712.sol";
import "./SafeERC20.sol";

contract ArkenTokenClaimIF is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    IERC20 public immutable arkenToken;
    address public validSigner;
    bytes32 constant CLAIM_TYPEHASH = keccak256(
        "Claim(uint256 amount,address account)"
    );

    mapping(address => bool) private _claimed;

    event Claim(
        uint256 amount,
        address account
    );

    constructor(address _arkenToken, address _signer)
        EIP712("ArkenTokenClaimIF", "1")
    {
        arkenToken = IERC20(_arkenToken);
        validSigner = _signer;
    }

    function updateSigner(address _signer) public onlyOwner {
        validSigner = _signer;
    }

    function claimed(address account) external view returns (bool) {
        return _claimed[account];
    }

    function claim(uint256 amount, bytes calldata signature) external {
        bytes32 hash = _hash(amount, msg.sender);
        require(!_claimed[msg.sender], "ArkenTokenClaimIF: already claimed");
        
        require(ECDSA.recover(hash, signature) == validSigner, "ArkenTokenClaimIF: invalid signature");
        
        arkenToken.safeTransfer(msg.sender, amount);
        _claimed[msg.sender] = true;
        
        emit Claim(amount, msg.sender);
    }

    function _hash(
        uint256 amount,
        address account
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        CLAIM_TYPEHASH,
                        amount,
                        account
                    )
                )
            );
    }
}
