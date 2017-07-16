
pragma solidity ^0.4.11;
import "./OraclizeAPI_0.4.sol";

contract USDOracle is usingOraclize {

  uint256 numEntries = 4;
  uint256[4] public datapoints;
  string[4] public urls;
  uint256 public timeBetweenUpdates;
  uint256 usdPerEth;
  uint256 gasCost;
  uint8 rateIndex;
  bool activeNestedQueries;
  address owner;
  mapping (bytes32 => uint8) queries;

  event LogNewOraclizeQuery(bytes32 id);
  event LogNewPriceData(bytes32 id, uint256 price, bytes ipfsProofMultihash);
  event LogNewPrice(uint256 price);
  event LogUrlUpdate(string oldUrl, string newUrl);
  event LogDuplicateResult(bytes32 id);
  event Deposit(uint256 amount);

  modifier onlyOwner() {
      require(msg.sender == owner);
      _;
  }

  function USDOracle() {
    oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
    owner = msg.sender;
    gasCost = 200000;
    timeBetweenUpdates = 2 * 60 * 60; // 2 hours
    urls[0] = "json(https://api.gemini.com/v1/pubticker/ethusd).last";
    urls[1] = "json(https://api.gdax.com/products/ETH-USD/ticker).price";
    urls[2] = "json(https://api.bitfinex.com/v1/pubticker/ethusd).last_price";
    urls[3] = "json(https://api.kraken.com/0/public/Ticker?pair=ETHUSD).result.XETHZUSD.c.0";
  }

  function changeUrl(uint256 index, string newUrl) onlyOwner {
    require(index < urls.length);
    require(!isEmpty(newUrl));
    string storage oldUrl = urls[index];
    urls[index] = newUrl;
    LogUrlUpdate(oldUrl, newUrl);
  }

  // refill balance
  function () payable {
    Deposit(msg.value);
  }

  function isEmpty(string data) internal constant returns (bool) {
    return bytes(data).length == 0;
  }

  function getRate() constant returns (uint256) {
    return usdPerEth;
  }

  function setGas(uint256 gas) onlyOwner {
      gasCost = gas;
  }

  function setGasPrice(uint256 price) onlyOwner {
    require(price > 0);
    oraclize_setCustomGasPrice(price);
  }

  function setTimeBetweenUpdates(uint256 _delay) onlyOwner {
    timeBetweenUpdates = _delay;
  }

  function seenResultAlready(bytes32 queryId) internal returns (bool) {
    return queries[queryId] > 1;
  }

  function __callback(bytes32 queryId, string result, bytes proof) {
    require(msg.sender == oraclize_cbAddress());

    // Oraclize is misbehaving and sending the same result more than once
    // we might as well start over from the beginning
    if (seenResultAlready(queryId)) {
      queries[queryId] += 1;
      LogDuplicateResult(queryId);
      activeNestedQueries = false;
      return update(0);
    }

    // Server did not return a valid response, discard old value and result
    // and continue with next data provider
    if (isEmpty(result)) {
      datapoints[rateIndex] = 0;
      rateIndex += 1;
      return update(0, rateIndex);
    }

    uint256 price = parseInt(result, 2);
    datapoints[rateIndex] = price;
    rateIndex += 1;
    queries[queryId] += 1;

    if (rateIndex < numEntries) {
      update(0, rateIndex);
    } else {
      uint256 sum = 0;
      for(uint8 i = 0; i < numEntries; i++) {
        sum += datapoints[i];
      }

      usdPerEth = (sum / numEntries) * 10**16;
      rateIndex = 0;
      require(usdPerEth > 0);
      LogNewPrice(usdPerEth);
      update(timeBetweenUpdates, 0); // start over after a delay
    }

    LogNewPriceData(queryId, price, proof);
  }

  /// @dev start a new nested update, anyone can do this as long as an update chain
  /// isn't already active
  /// @param delay how long to wait until performing first query
  /// Note: subsequent queries use the _timeBetweenUpdates_ delay
  function update(uint256 delay) payable {
    require(!activeNestedQueries); // we don't want to interleave updates
    if (msg.value > 0) {
      Deposit(msg.value);
    }
    activeNestedQueries = true;
    update(delay, 0);
  }

  function update(uint256 delay, uint256 urlId) internal {
    uint256 remainingQueries = (numEntries - urlId);

    // If this is true here it was likely triggered by last result in a batch
    // so we can just silently abort
    if (remainingQueries * oraclize_getPrice("URL") > this.balance) {
      activeNestedQueries = false;
      return;
    }

    bytes32 queryId = oraclize_query(delay, "URL", urls[urlId], gasCost);
    queries[queryId] += 1;

    // oraclize should never return the same query id twice
    require(queries[queryId] == 1);
    LogNewOraclizeQuery(queryId);
  }

  function suicide() onlyOwner {
    selfdestruct(owner);
  }
}
