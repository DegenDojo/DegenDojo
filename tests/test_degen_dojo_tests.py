from scripts.helper import get_account, get_account2
from brownie import DegenDojo, DojoBar, DojoHouse
import pytest
import time
from web3 import Web3

LIQUIDITY_AMOUNT = Web3.toWei(30, "ether")
LARGE_TRADE = Web3.toWei(0.7, "ether")
SMALL_TRADE = Web3.toWei(0.2, "ether")


def test_make_spin_trade():
    account = get_account()
    dojo_token = DegenDojo[-1]
    dojo_house = DojoHouse[-1]
    # first make sure theres no tokens to claim
    if dojo_token.checkPendingTrade(account) == True:
        dojo_token.claimTrade({"from": account})
    if dojo_house.balance() < LIQUIDITY_AMOUNT:
        tx = dojo_house.enter({"from": account, "value": LIQUIDITY_AMOUNT})
        tx.wait(1)
    print("min trade:")
    print(dojo_token.getMinimumTradeSize())
    print("max trade:")
    print(dojo_token.getMaximumTradeSize())
    starting_balance = account.balance()
    # make a trade for 0.05 eth using belt 1
    dojo_token.initiateTrade(1, {"from": account, "value": LARGE_TRADE})
    # check eth has been deducted from balance
    assert account.balance() <= starting_balance - LARGE_TRADE
    # make sure we cannot make another trade while this is pending
    with pytest.raises(Exception):
        dojo_token.initiateTrade(1, {"from": account, "value": LARGE_TRADE})
    # make sure we cannot make another small trade while this is pending
    with pytest.raises(Exception):
        dojo_token.initiateSmallTrade(1, {"from": account, "value": SMALL_TRADE})
    # wait for VRF coordinator
    time.sleep(180)
    # get the initial house balance
    dojo_bar = DojoBar[-1]
    initial_bar_balance = dojo_bar.balance()
    # check we can now claim trade after 3 minutes
    tx = dojo_token.claimTrade({"from": account})
    tx.wait(1)
    # check cannot claim trade again
    with pytest.raises(Exception):
        dojo_token.claimTrade({"from": account})
    # check that our balance has been increased with getting back at least half our money back
    assert account.balance() >= starting_balance - (LARGE_TRADE * 0.51)
    # check that amount received is less than maximum payout
    assert account.balance() <= starting_balance + (LARGE_TRADE * 2)
    # withdraw back the 2 eth
    remainder = dojo_house.balanceOf(account)
    dojo_house.leave(remainder, {"from": account})
    # check to see that the bar was issued fees
    assert dojo_bar.balance() > initial_bar_balance


def test_make_allornotihng_trade():
    account = get_account()
    dojo_token = DegenDojo[-1]
    dojo_house = DojoHouse[-1]
    # first make sure theres no tokens to claim
    if dojo_token.checkPendingTrade(account) == True:
        dojo_token.claimTrade({"from": account})
    # fund the house with 2 eth so there is enough liqudiity to make trades
    if dojo_house.balance() < LIQUIDITY_AMOUNT:
        tx = dojo_house.enter({"from": account, "value": LIQUIDITY_AMOUNT})
        tx.wait(1)
    starting_balance = account.balance()
    # make a trade for 0.05 eth using belt 4
    tx = dojo_token.initiateTrade(4, {"from": account, "value": LARGE_TRADE})
    tx.wait(1)
    # check eth has been deducted from balance
    assert account.balance() <= starting_balance - (LARGE_TRADE)
    # make sure we cannot make another trade while this is pending
    with pytest.raises(Exception):
        dojo_token.initiateTrade(4, {"from": account, "value": LARGE_TRADE})
    # make sure we cannot make another small trade while this is pending
    with pytest.raises(Exception):
        dojo_token.initiateSmallTrade(1, {"from": account, "value": SMALL_TRADE})
    # wait for VRF coordinator
    time.sleep(180)
    # get the initial house balance
    dojo_bar = DojoBar[-1]
    initial_bar_balance = dojo_bar.balance()
    # check we can now claim trade after 3 minutes
    dojo_token.claimTrade({"from": account})
    # check cannot claim trade again
    with pytest.raises(Exception):
        dojo_token.claimTrade({"from": account})
    # check that our balance has either not moved, or increased to greater than starting
    assert (
        account.balance() > starting_balance
        or account.balance() <= starting_balance - LARGE_TRADE
    )
    # withdraw back the 2 eth
    remainder = dojo_house.balanceOf(account)
    dojo_house.leave(remainder, {"from": account})
    # check to see that the bar was issued fees
    assert dojo_bar.balance() > initial_bar_balance


def test_make_small_trade():
    account = get_account()
    account2 = get_account2()
    dojo_token = DegenDojo[-1]
    dojo_house = DojoHouse[-1]
    # first make sure theres no tokens to claim
    if dojo_token.checkPendingTrade(account) == True:
        dojo_token.claimTrade({"from": account})
    # fund the house with 2 eth so there is enough liqudiity to make trades
    tx = dojo_house.enter({"from": account, "value": LIQUIDITY_AMOUNT})
    tx.wait(1)
    starting_balance = account.balance()
    # make a small trade for 0.02 eth using belt 4
    tx = dojo_token.initiateSmallTrade(4, {"from": account, "value": SMALL_TRADE})
    tx.wait(1)
    # check eth has been deducted from balance
    assert account.balance() <= starting_balance - (SMALL_TRADE)
    # make sure we cannot claim trade
    with pytest.raises(Exception):
        dojo_token.claimTrade({"from": account})
    # make sure we cannot make another trade while this is pending
    with pytest.raises(Exception):
        dojo_token.initiateTrade(4, {"from": account, "value": LARGE_TRADE})
    # make sure we cannot make another small trade while this is pending
    with pytest.raises(Exception):
        dojo_token.initiateSmallTrade(1, {"from": account, "value": SMALL_TRADE})
    # make a larger trade with different account
    tx2 = dojo_token.initiateTrade(4, {"from": account2, "value": LARGE_TRADE})
    tx.wait(1)
    # wait for VRF coordinator
    time.sleep(180)
    # get the initial house balance
    dojo_bar = DojoBar[-1]
    initial_bar_balance = dojo_bar.balance()
    # check we can now claim trade after 3 minutes
    tx3 = dojo_token.claimTrade({"from": account})
    tx3.wait(1)
    # check that other account can claim trade
    tx4 = dojo_token.claimTrade({"from": account2})
    tx4.wait(1)
    # check that our balance has doubled, or lose the balance
    assert (
        account.balance() > starting_balance + (SMALL_TRADE * 0.95)
        or account.balance() <= starting_balance - SMALL_TRADE
    )
    # check cannot claim trade again
    with pytest.raises(Exception):
        dojo_token.claimTrade({"from": account})
    with pytest.raises(Exception):
        dojo_token.claimTrade({"from": account2})
    # withdraw back the 2 eth
    remainder = dojo_house.balanceOf(account)
    dojo_house.leave(remainder, {"from": account})
    # check to see that the bar was issued fees
    assert dojo_bar.balance() > initial_bar_balance
