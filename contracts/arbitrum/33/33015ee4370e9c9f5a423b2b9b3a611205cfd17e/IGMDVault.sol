pragma solidity ^0.8.12;

import "./IERC20.sol";

interface IGMDVault is IERC20 {
    function enter(uint256 _amountin, uint256 _pid) external;
    function leave(uint256 _share, uint256 _pid) external returns (uint256);

    function enterETH(uint256 _pid) external payable;
    function leaveETH(uint256 _share, uint256 _pid) external payable;

    function poolInfo(uint256) external view returns (PoolInfo memory);

    function GDpriceToStakedtoken(uint256 _pid) external view returns(uint256);
    function displayStakedBalance(address _address, uint256 _pid) external view returns (uint256);

    struct PoolInfo {
        IERC20 lpToken;    
        GDtoken GDlptoken; 
        uint256 EarnRateSec;     
        uint256 totalStaked; 
        uint256 lastUpdate; 
        uint256 vaultcap;
        uint256 glpFees;
        uint256 APR;
        bool stakable;
        bool withdrawable;
        bool rewardStart;
    }



    function setPoolCap(uint256 _pid, uint256 _vaultcap) external;
}

interface IGMDBfrPool {
        function poolInfo(uint256) external view returns (PoolInfo memory);

        struct PoolInfo {
            IERC20 lpToken;    
            GDtoken GDlptoken; 
            uint256 EarnRateSec;     
            uint256 totalStaked; 
            uint256 lastUpdate; 
            uint256 vaultcap;
            uint256 BlpFees;
            uint256 APR;
            bool stakable;
            bool withdrawable;
            bool rewardStart;
    }
}

interface GDtoken is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external ;
}
