package com.phono.impl
{
	import com.phono.Audio;
	import com.phono.Codec;
	import com.phono.Share;
	
	import flash.events.Event;
	import flash.events.TimerEvent;
	import flash.media.Microphone;
	import flash.media.Sound;
	import flash.media.SoundChannel;
	import flash.media.SoundCodec;
	import flash.media.SoundMixer;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.net.ObjectEncoding;
	import flash.net.Responder;
	import flash.utils.ByteArray;
	import flash.utils.Timer;
	import flash.utils.setTimeout;
	
	import flashx.textLayout.formats.Float;
	
	import mx.utils.*;
	
	public class RtmpShare implements Share
	{
		private const ECHO_TICKER_MS:int = 50;
		
		private var _audio:Audio;
		private var _nc:NetConnection;
		private var _tx:NetStream;
		private var _streamName:String;
		private var _url:String;
		private var _tones:Tones;
		private var _codec:Codec;
		private var _gain:Number;
		private var _mute:Boolean = false;
		private var _suppress:Boolean = false;
		private var _queue:Array;
		private var _mic:Microphone;
		private var _active:Boolean = false;		
		private var _tail:int = 0;
		
		private var _soundTimer:Timer = new Timer(ECHO_TICKER_MS, 0);
		
		public function RtmpShare(queue:Array, nc:NetConnection, streamName:String, codec:Codec, url:String, mic:Microphone, suppress:Boolean)
		{
			_nc = nc;
			_streamName = streamName;
			_url = url;
			_tones = new Tones();
			_codec = codec;
			_suppress = suppress;
			_mic = mic;
			_mic.setSilenceLevel(0,2000);
			_mic.gain = 50;
					
			_gain = _mic.gain;
			_mic.setUseEchoSuppression(true);			
			_queue = queue;
			
			if (codec.name.toUpperCase() == "SPEEX") {
				_mic.codec = SoundCodec.SPEEX;				
			} else _mic.codec = SoundCodec.SPEEX; // Anyway for now..			
			_mic.framesPerPacket = 1;
			
			_soundTimer.addEventListener(TimerEvent.TIMER, onSoundTicker);
		}

		public function start():void
		{
			if (!_nc.connected) _queue.push(this.start);
			else {
					
				// Start the stream				
				if (_mic) {
					_tx = new NetStream(_nc);	
					
					_tx.client = this;
					_tx.attachAudio(_mic);
					_tx.publish(_streamName, "live");
				
					if (_suppress) {						
						_soundTimer.start();
					}
					_active = true;
				}
			}
		}
		
		public function stop():void
		{
			if (!_nc.connected) _queue.push(this.stop);
			if (_tx != null) _tx.close();
			_soundTimer.stop();
			_active = false;
		}
		
		public function digit(digit:String, duration:Number=250, audible:Boolean=true):void
		{
			var onResult:Function = function(result:Object):void 
			{
				trace("sendDigit result:"+ObjectUtil.toString(result));
			};
			var onFault:Function = function(fault:Object):void 
			{
				trace("sendDigit: fault:"+ObjectUtil.toString(fault));
			};            
			
			if (audible) _tones.play(digit, duration);
			_nc.call("sendDigit", new Responder(onResult, onFault), _streamName, digit);
		}
		
		public function get URL():String 
		{
			return _url;
		}
		
		public function get codec():Codec
		{
			return _codec;
		}
		
		public function get gain():Number
		{
			return _gain;
		}
		
		public function set gain(value:Number):void
		{
			trace("gain: " + value);
			_gain = value;	
			if (!_mute) _mic.gain = _gain;
		}
		
		public function set mute(value:Boolean):void
		{
			trace("mute: " + value);
			_mute = value;
			if (_mute) {
				if (_suppress && _active) _soundTimer.stop();
				_mic.gain = 0;
			} else {
				if (_suppress && _active) _soundTimer.start();
				_mic.gain = _gain;
			}
		}
		
		public function get mute():Boolean
		{
			return _mute;
		}		
		
		public function set suppress(value:Boolean):void
		{
			trace("suppress: " + value);
			_suppress = value;
			if (_suppress) {
				if (!_mute && _active) _soundTimer.start();
			}
			else if (_active) _soundTimer.stop();
		}
		
		public function get suppress():Boolean
		{
			return _suppress;
		}
		
		private function onSoundTicker(event:Event):void {
			const CHANNEL_LENGTH:int = 256;
			const SUPPRESS_THRESHOLD:Number = 1;
			const ECHO_TAIL_MS:int = 200;
			
			var bytes:ByteArray = new ByteArray();			
			var n:Number = 0;
			
			if (!SoundMixer.areSoundsInaccessible()) {
				try {
					SoundMixer.computeSpectrum(bytes, false, 0);
					for (var i:int = 0; i < CHANNEL_LENGTH; i++) {
						n += Math.abs(bytes.readFloat());
					}
					//trace("c: " + n);
					// If we have audio, then set a tail
					if (n > SUPPRESS_THRESHOLD)
					{
						_tail = ECHO_TAIL_MS/ECHO_TICKER_MS;
					}
					// If we have a tail then disable the mic
					if (_tail > 0) {
						//trace("t: " + _tail);
						_tail = _tail - 1;
						_mic.gain = 0;	
					} else {
						if (!_mute) _mic.gain = _gain;	
					}
				} catch (e:Error) {
					trace("Error accessing samples, stop suppressing");
					trace(e);
					_soundTimer.stop();
					_suppress = false;
					if (!_mute) _mic.gain = _gain;
				}
			}
		}			
	}
}