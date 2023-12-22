pragma solidity >=0.8.0;

interface IGLPManager {
	function getAum(bool maximise) external view returns (uint256);

	function getAumInUsdg(bool maximise) external view returns (uint256);

	function glp() external view returns (address);
}

