interface IController {
    function whiteListDex(address, bool) external returns(bool);
    function adminPause() external; 
    function adminUnPause() external;
    function isWhiteListedDex(address) external returns(bool);
}
