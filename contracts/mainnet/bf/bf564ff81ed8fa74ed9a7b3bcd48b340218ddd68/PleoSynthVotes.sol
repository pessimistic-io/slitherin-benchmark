// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Votes.sol";
import "./Ownable.sol";
import "./IPleoSynthVotesToken.sol";

/**
 * for Pleo-Synth governance votes.
 */
contract PleoSynthVotes is Votes,Ownable {

    address[] private _tokens;
    uint256 private _nums = 0;

    constructor(address[] memory tokens) EIP712("pleosynth.xyz","1.0") {
        _tokens = tokens;
    }

    /**
     *
     * Emits a {IVotes-DelegateVotesChanged} 
     */
    function transferVotingUnits(
        address from,
        address to,
        uint256 batchSize
    ) public virtual {
        _nums += 1;
        super._transferVotingUnits(from, to, batchSize);
    }

    /**
     * @dev Returns the balance of `account`.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        uint256 votingUnits = 0;
        for(uint256 i=0;i<_tokens.length;i++){
            votingUnits += IPleoSynthVotesToken(_tokens[i]).balanceOf(account);
        }
        return votingUnits;
    }

    function getNum() public view returns(uint256) {
        return _nums;
    }

    function setTokensAddr(address[] memory tokensAddr) public onlyOwner {
        _tokens = tokensAddr;
    }

    function getTokensAddr() public view returns(address[] memory) {
        return _tokens;
    }
}

