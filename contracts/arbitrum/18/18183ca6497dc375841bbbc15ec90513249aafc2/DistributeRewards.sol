// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ECDSA.sol";
import "./Ownable.sol";


contract DistributeRewards is ReentrancyGuard,Ownable{
    using SafeERC20 for IERC20;

    struct Claim{
        address user;
        address token;
        uint256 amount;
        uint256 nonce;//Change until receive the event
        bytes32 Hash;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }
   
    bool public pause;
    mapping (address => bool) public signers;
    mapping (address => uint256) public claimNonce;
    
    event logSigner(address signer, bool isRemoval);
    event logClaimRewards(address user, bytes32 Hash, uint256 amount, uint256 nonce);

    modifier notPause() {
        require(!pause, "REWARDS:PAUSING_NOW");
        _;
    }

    function getTokenAmountInpool(address token) public view returns(uint256){
        return IERC20(token).balanceOf(address(this));
    }

    function setPause(bool pauseOrNot_) external onlyOwner {
        pause = pauseOrNot_;
    }

    function updateSigners(address[] memory toAdd, address[] memory toRemove)
        public
        virtual
        onlyOwner
    {
        for (uint256 i = 0; i < toAdd.length; i++) {
            signers[toAdd[i]] = true;
            emit logSigner(toAdd[i], false);
        }
        for (uint256 i = 0; i < toRemove.length; i++) {
            delete signers[toRemove[i]];
            emit logSigner(toRemove[i], true);
        }
    }

    function claimRewards(Claim memory input) external nonReentrant notPause{
        require(input.token != address(0), "Invalid token address");
        require(msg.sender == input.user, "WRONG_USER");
        require(claimNonce[msg.sender] == input.nonce, "WRONG_ORDER");
        
        _verifyInputSignature(input);
        claimNonce[msg.sender] = claimNonce[msg.sender] + 1;

        IERC20 returnToken = IERC20(input.token);
        require(returnToken.balanceOf(address(this)) >= input.amount, "TOKEN_IS_NOT_ENOUGHT_PLZ_CONTACT_ADMIN");

        returnToken.safeTransfer(msg.sender, input.amount);
        
        emit logClaimRewards(input.user, input.Hash, input.amount, input.nonce);
    }

    function _verifyInputSignature(Claim memory input) internal virtual {
        bytes32 hash = keccak256(abi.encode(input.user, input.token, input.amount, input.nonce));
        require(hash == input.Hash, "WRONG_ENCODE");
        address signer = ECDSA.recover(hash, input.v, input.r, input.s);
        require(signers[signer], 'Input signature error');
    } 

    function rescueFunds(
        address token,
        address userAddress,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(userAddress, amount);
    }

}

