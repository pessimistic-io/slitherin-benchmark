pragma solidity >0.6.12;

interface IBasisAsset {
    function mint(address recipient, uint amount) external;

    function burn(uint amount) external;

    function burnFrom(address from, uint amount) external;

    function isOperator() external returns (bool);

    function amIOperator() external view returns (bool);

    function transferOperator(address newOperator_) external;
}

