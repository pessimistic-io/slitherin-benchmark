pragma solidity 0.8.10;

interface IAspisGovernanceERC20 {

    function decimals() external view returns(uint8);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
   
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

}

