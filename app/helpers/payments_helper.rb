module PaymentsHelper
  # The UPI QR as inline SVG (exact amount filled in), drawn on the server with rqrcode
  def upi_qr_svg(uri)
    RQRCode::QRCode.new(uri).as_svg(module_size: 5, standalone: true, use_path: true, viewbox: true,
                                    svg_attributes: { class: "h-56 w-56", role: "img", "aria-label": "UPI QR code" }).html_safe
  end

  def rupees(amount) = "₹#{number_with_delimiter(amount)}"

  def payment_status_chip(payment)
    klass = { "approved" => "bg-emerald-50 text-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300",
              "rejected" => "bg-red-50 text-red-800 dark:bg-red-950/40 dark:text-red-300",
              "pending"  => "bg-amber-50 text-amber-800 dark:bg-amber-950/40 dark:text-amber-300" }
              .fetch(payment.status, "bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300")
    tag.span(payment.status_label, class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{klass}")
  end
end
