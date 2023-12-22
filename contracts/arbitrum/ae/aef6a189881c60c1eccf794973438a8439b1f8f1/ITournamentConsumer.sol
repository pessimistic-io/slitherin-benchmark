pragma solidity 0.8.17;

// interface for chainlink random time interval
interface ITournamentConsumer {

    // @dev request a random number if current epoch has not been filled
	function update() external;

    // @dev return current epoch
    function currentEpoch() external view returns (uint256);

    // @dev return if update is possible
    function canUpdate() external view returns (bool);
}
