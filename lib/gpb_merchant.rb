# encoding: utf-8
require 'gpb_merchant/version'
require 'uri'

module GpbMerchant

  extend self

  def debug(v = nil)

    @debug = (v === true) unless v.nil?
    @debug

  end # debug

  def debug?
    @debug === true
  end # debug?

  def login(v = nil)

    @login = v unless v.nil?
    @login

  end # login

  def password(v = nil)

    @password = v unless v.nil?
    @password

  end # password

  def merch_id(v = nil)

    @merch_id = v unless v.nil?
    @merch_id

  end # merch_id

  def account_id(v = nil)

    @account_id = v unless v.nil?
    @account_id

  end # account_id

  def pps_url(v = nil)

    @pps_url = v unless v.nil?
    @pps_url

  end # pps_url

  def success_payment_callback(v = nil)

    unless v.nil?

      raise ArgumentError, "Argument must be a proc or lambda" unless v.is_a?(::Proc)
      @success_payment_callback = v

    end

    @success_payment_callback

  end # success_payment_callback

  def failure_payment_callback(v = nil)

    unless v.nil?

      raise ArgumentError, "Argument must be a proc or lambda" unless v.is_a?(::Proc)
      @failure_payment_callback = v

    end

    @failure_payment_callback

  end # failure_payment_callback

  # Путь к файлу сертифката
  def cert_file(v = nil)

    unless v.nil?

      raise ArgumentError, "File #{v} not found" unless File.exist?(v)
      @cert_file = File.read(v)

    end

    @cert_file

  end # cert_file

  def fullhostpath(v = nil)

    @fullhostpath = URI.parse(v) unless v.nil?
    @fullhostpath

  end # fullhostpath

  # Ссылка на оплату заказа
  def url_for_payment(order_uri, back_url_success = nil, back_url_failure = nil)

    order = ::GpbTransaction.where(:order_uri => order_uri).first
    return unless order

    uri = ::URI.encode_www_form({

      :lang         => "RU",
      :merch_id     => self.merch_id,
      :back_url_s   => back_url_success,
      :back_url_f   => back_url_failure || back_url_success,
      "o.order_uri" => order_uri,
      "o.amount"    => order.price

    })

    "#{pps_url}?#{uri}"

  end # url_for_payment

  # Проверка возможности приема платежа
  def check_payment(params)

    result, msg, id = ::GpbTransaction.check({

      trx_id:     params[:trx_id],
      merch_id:   params[:merch_id],
      order_uri:  params[:order_uri],
      amount:     (params[:amount].try(:to_i) || 0),
      checked_at: params[:checked_at].try(:to_time).try(:utc)

    })

    ::GpbMerchant::XmlBuilder.check_response({

      order_uri:        params[:order_uri],
      merchant_trx_id:  id,
      amount:           (params[:amount].try(:to_i) || 0),
      currency:         643,
      desc:             msg

    }, result)

  end # check_payment

  # Регистрация результата платежа
  def register_payment(params)

    unless params[:transmission_at].nil?

      # Разбираем время авторизационного запроса в формате «MMddHHmmss»
      time = Date._strptime(params[:transmission_at], "%m%d%H%M%S") rescue nil

      if time

        # Пробуем преобразовать в дату
        transmission_at = ::Time.utc(
          Time.now.year,
          time[:mon],
          time[:mday],
          time[:hour],
          time[:min],
          time[:sec]
        ) rescue nil

      end # if

    end # unless

    result, msg = ::GpbTransaction.complete({

      merch_id:     params[:merch_id],
      trx_id:       params[:trx_id],
      merchant_trx: params[:merchant_trx],

      order_uri:    params[:order_uri],

      result_code:  (params[:result_code].try(:to_i) || 0),
      amount:       (params[:amount].try(:to_i) || 0),

      account_id:   params[:account_id],
      rrn:          params[:rrn],

      transmission_at: transmission_at,
      payed_at:     params[:payed_at].try(:to_time).try(:utc),

      card_holder:  params[:card_holder],
      card_masked:  params[:card_masked],

      # TODO: пока не знаю, что с этим параметром делать
      fully_auth:   params[:fully_auth] == 'Y',

      verified:     params[:verified]

    })

    ::GpbMerchant::XmlBuilder.register_response({
      desc: msg
    }, result)

  end # register_payment

  # Выставление счета
  def init_payment(order_uri)
    ::GpbTransaction.init(order_uri)
  end # init_payment

  # Отмена платежа
  def cancel_payment(order_uri)
    ::GpbTransaction.cancel(order_uri)
  end # cancel_payment

  # Статус оплаты
  def status_bill(order_uri)

    ::GpbTransaction.status({
      merch_id:  ::GpbMerchant::merch_id,
      order_uri: order_uri
    })

  end # status_bill

  # signature in Base64
  def verify_signature(signature)

    return false if ::GpbMerchant.cert_file.blank?
    return false if fullhostpath.nil?

    data = fullhostpath.to_s
    public_key = OpenSSL::X509::Certificate.new(::GpbMerchant.cert_file).public_key
    public_key.verify(OpenSSL::Digest::SHA1.new(data), Base64.decode64(signature), data)

  end # verify_signature

  def construct_data(path, query)

    return false if fullhostpath.nil?

    fullhostpath.path   = path
    fullhostpath.query  = query.gsub(/&signature=.+$/, "")
    fullhostpath

  end # construct_data

  # Логирование
  def log(str, mark = "GpbMerchant")

    if mark

      ::Rails.logger.tagged("#{::Time.now}. #{mark}") {
        ::Rails.logger.error(str)
      }

    else
      ::Rails.logger.error("#{::Time.now}. #{str}")
    end

    str

  end # log

  # Выбирамем ближайший рабочий день для указанной даты
  def correct_date(date, delta = 6)

    return if date.nil?

    delta       = 0 if delta < 0
    delta_hours = delta.hours

    t = date.to_time.utc + delta_hours

    if t.hour >= delta
      t = ::Time.new(t.year, t.month, t.day, 0, 0, 0) + 1.day
    else
      t = ::Time.new(t.year, t.month, t.day, 0, 0, 0)
    end

    while ::Calendar.holiday?(t)
      t += 1.day
    end

    (t.utc + delta_hours)

  end # correct_date

end # GpbMerchant

require 'gpb_merchant/xml'
require 'gpb_merchant/engine'
require 'gpb_merchant/railtie'
