interface IUniswapV2Pair {
	event Approval(address indexed owner, address indexed spender, uint value);
	event Transfer(address indexed from, address indexed to, uint value);

	function approve(address spender, uint value) external returns (bool);

	function allowance(address owner, address spender) external view returns (uint);

	function transfer(address to, uint value) external returns (bool);

	function transferFrom(address from, address to, uint value) external returns (bool);

	function burn(address to) external returns (uint amount1, uint amount2);

	function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

	function balanceOf(address user) external view returns (uint amount);

	function token0() external view returns (address);

	function token1() external view returns (address);

	function totalSupply() external view returns (uint256);

	function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

	event Mint(address indexed sender, uint amount0, uint amount1);
	event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
}

