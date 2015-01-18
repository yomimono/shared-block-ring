(*
 * Copyright (C) 2013 Citrix Systems Inc
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

module type BLOCK =
  V1.BLOCK
  with type 'a io = 'a Lwt.t
  and type page_aligned_buffer = Cstruct.t

module type RING = sig
  type t
  (* A ring containing variable-sized messages *)

  type block
  (* A block device *)

  val attach: block -> [ `Ok of t | `Error of string ] Lwt.t
  (** [attach blockdevice] attaches to a previously-created shared ring on top
      of [blockdevice]. *)

  type position with sexp_of
  (** A position within the ring *)

  val advance: t -> position -> [ `Ok of unit | `Error of string ] Lwt.t
  (** [advance t position] exposes the item associated with [position] to
      the Consumer so it can be [pop]ped. *)
end

module type PRODUCER = sig
  include RING

  val create: block -> [ `Ok of t | `Error of string ] Lwt.t
  (** [create blockdevice] initialises a shared ring on top of [blockdevice]
      where we will be able to [push] variable-sized items. *)

  val push: t -> Cstruct.t -> [ `Ok of position | `TooBig | `Retry | `Error of string ] Lwt.t
  (** [push t item] pushes [item] onto the ring [t] but doesn't expose it to
      the Consumer.
      [`Ok position] means the update has been safely written to the block device
      and can be exposed to the Consumer by calling [advance position].
      [`TooBig] means the item is too big for the ring: we adopt the convention
      that items must be written to the ring in one go
      [`Retry] means that the item should fit but there is temporarily not
      enough space in the ring. The client should retry later. *)
end

module type CONSUMER = sig
  include RING

  val pop: t -> [ `Ok of position * Cstruct.t | `Retry | `Error of string ] Lwt.t
  (** [pop t] returns a pair [(position * item)] where [item] is the next
      item on the ring. Repeated calls to [pop t] will return the same [item].
      To indicate that the item has been processed, call [advance position].
      [`Retry] means there is no item available at the moment and the client should
      try again later. *)

  val peek: t -> position -> [ `Ok of position * Cstruct.t | `Retry | `Error of string ] Lwt.t
  (** [peek t position] behaves like [pop t] would after a call to [advance position]
      i.e. it allows subsequent queue entries to be examined non-destructively. *)
end
