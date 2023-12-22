pragma solidity >=0.8.19;

/**
 * @title Commmunity Deployer Interface.
 */
interface ICommunityDeployer {
    // This event is triggered whenever a call to cast a vote succeeds
    event Voted(uint256 index, address account, uint256 numberOfVotes, bool yesVote);

    function hasVoted(uint256 index) external view returns (bool);
  
    function deploy() external;

    function queue() external;

    function castVote(
      uint256 _index, 
      uint256 _numberOfVotes, 
      bool _yesVote, 
      bytes32[] calldata _merkleProof
    ) external;
}

