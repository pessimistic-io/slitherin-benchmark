// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.16;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./draft-EIP712.sol";
import "./SafeERC20.sol";

contract ArkenTokenClaim is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    IERC20 public immutable arkenToken;
    address[3] public signers;
    bytes32 constant CLAIM_TYPEHASH = keccak256(
        "Claim(uint256 amount,address account,uint8 kind)"
    );

    mapping(uint8 => mapping (address => bool)) private _claimed;

    enum Kind {
        THANKYOU,
        FOLLOW_AND_SHARE,
        ARKEN_AIRDROP_1
    }

    event Claim(
        uint256 amount,
        address account,
        Kind kind
    );

    constructor(address _arkenToken, address[3] memory _signers)
        EIP712("ArkenTokenClaim", "1")
    {
        arkenToken = IERC20(_arkenToken);
        signers = _signers;
    }

    function updateSigner(address[3] memory _signers) public onlyOwner {
        signers = _signers;
    }

    function claimed(Kind kind, address account) external view returns (bool) {
        return _claimed[uint8(kind)][account];
    }

    function claim(uint256 amount, bytes calldata signature, Kind kind) external {
        bytes32 hash = _hash(amount, msg.sender, kind);
        require(!_claimed[uint8(kind)][msg.sender], "ArkenTokenClaim: already claimed");
        
        address validSigner = signers[uint256(kind)];
        require(ECDSA.recover(hash, signature) == validSigner, "ArkenTokenClaim: invalid signature");
        
        arkenToken.safeTransfer(msg.sender, amount);
        _claimed[uint8(kind)][msg.sender] = true;
        
        emit Claim(amount, msg.sender, kind);
    }

    function _hash(
        uint256 amount,
        address account,
        Kind kind
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        CLAIM_TYPEHASH,
                        amount,
                        account,
                        kind
                    )
                )
            );
    }
}
