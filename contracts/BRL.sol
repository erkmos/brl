pragma solidity ^0.4.11;

import './SafeMath.sol';
import './Ownable.sol';
import './USDOracle.sol';

contract BRL is Ownable {
  using SafeMath for uint256;

  uint256 public totalSupply;
  mapping(address => uint) balances;
	mapping (address => mapping (address => uint256)) allowed;
  string public constant name = "Bitcoin Resistant Ledger";
  string public constant symbol = "BRL";
  uint8 public constant decimals = 18;

  address fundsWallet;

  // tokens are transferable starting at 2017-08-14 00:00 UTC
  uint64 public transferDate = 1502668800;
  USDOracle usdOracle;

  modifier transferrable() {
    require(now >= transferDate);
    _;
  }

  modifier saleActive() {
    require(now < transferDate);
    _;
  }

  event Approval(address indexed owner, address indexed spender, uint value);
  event Transfer(address indexed from, address indexed to, uint value);
  event Created(address indexed owner, uint256 ethAmount, uint256 tokens);
  event Destroyed(address indexed owner, uint256 amount);

  function BRL(address wallet, address _oracle) {
    require(wallet != address(0));
    require(_oracle != address(0));
    usdOracle = USDOracle(_oracle);
    fundsWallet = wallet;
  }

  function ethToTokens(uint256 amount) constant returns (uint256) {
    require(amount > 0);
    uint256 rate = usdOracle.getRate();
    require(rate > 0);
    return rate.mul(amount).div(10**18);
  }

  function () payable saleActive {
    uint256 tokenAmount = ethToTokens(msg.value);
    balances[msg.sender] = balances[msg.sender].add(tokenAmount);
    totalSupply = totalSupply.add(tokenAmount);

    fundsWallet.transfer(msg.value);
    Created(msg.sender, msg.value, tokenAmount);
  }

  function burn(uint256 amount) {
    balances[msg.sender] = balances[msg.sender].sub(amount);
    totalSupply = totalSupply.sub(amount);
    Destroyed(msg.sender, amount);
  }

  function transfer(address _to, uint _value) transferrable {
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
  }

  function balanceOf(address _owner) constant returns (uint balance) {
    return balances[_owner];
  }

  function transferFrom(address _from, address _to, uint256 _value) transferrable {
    var _allowance = allowed[_from][msg.sender];

    balances[_to] = balances[_to].add(_value);
    balances[_from] = balances[_from].sub(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    Transfer(_from, _to, _value);
  }

  function approve(address _spender, uint256 _value) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
  }

  function allowance(address _owner, address _spender)
  constant returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }
}
