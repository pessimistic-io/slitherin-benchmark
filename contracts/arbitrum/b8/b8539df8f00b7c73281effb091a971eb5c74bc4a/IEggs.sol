interface IEggsToken {
	function mint(address to, uint256 amount) external;

	function mintUnderlying(address to, uint256 amount) external returns (bool);

	function totalSupply() external view returns (uint256);

	function transfer(address to, uint256 value) external returns (bool);

	function transferUnderlying(address to, uint256 value) external returns (bool);

	function fragmentToEggs(uint256 value) external view returns (uint256);

	function eggsToFragment(uint256 eggs) external view returns (uint256);

	function balanceOfUnderlying(address who) external view returns (uint256);

	function burn(uint256 amount) external;

	function rebase() external;
}

