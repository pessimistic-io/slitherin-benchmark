pragma solidity ^0.8.14;

interface IStakedDarwin {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns(string calldata);
    function symbol() external pure returns(string calldata);
    function decimals() external pure returns(uint8);

    function darwinStaking() external view returns (address);
    function totalSupply() external view returns (uint);
    function balanceOf(address user) external view returns (uint);

    function mint(address to, uint value) external;
    function burn(address from, uint value) external;

    function setDarwinStaking(address _darwinStaking) external;
}
